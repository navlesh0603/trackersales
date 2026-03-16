import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:trackersales/models/trip.dart';
import 'package:trackersales/providers/auth_provider.dart';
import 'package:trackersales/providers/trip_provider.dart';
import 'package:trackersales/providers/notification_provider.dart';
import 'package:trackersales/theme/app_theme.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:trackersales/utils/permission_util.dart';
import 'package:trackersales/widgets/end_trip_dialog.dart';
import 'package:trackersales/services/attendance_service.dart';

class TripDetailScreen extends StatefulWidget {
  final Trip trip;
  final bool canStart;

  const TripDetailScreen({super.key, required this.trip, this.canStart = true});

  @override
  State<TripDetailScreen> createState() => _TripDetailScreenState();
}

class _TripDetailScreenState extends State<TripDetailScreen>
    with WidgetsBindingObserver {
  late Trip _trip;
  bool _isLoading = true;
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  GoogleMapController? _mapController;
  final String _googleApiKey = "AIzaSyCzdKwyS3klmlBOhoJWChkd7kcFptE83yw";
  final AttendanceService _attendanceService = AttendanceService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _trip = widget.trip;
    _checkPermissionAndFetch();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      PermissionUtil.checkMandatoryPermissions(context);
    }
  }

  Future<void> _checkPermissionAndFetch() async {
    await PermissionUtil.checkMandatoryPermissions(context);
    _fetchDetails();
  }

  Future<void> _fetchDetails() async {
    final user = Provider.of<AuthProvider>(context, listen: false).user;
    if (user != null && _trip.tripId != null) {
      final tripProvider = Provider.of<TripProvider>(context, listen: false);
      final result = await tripProvider.fetchTripDetails(
        systemUserId: user.systemUserId,
        tripsId: _trip.tripId!,
      );

      if (mounted && result['success']) {
        final stops = result['stops'] as List<dynamic>? ?? [];
        final tripData = result['trip_data'];

        final path = stops.map((stop) {
          final lat = double.tryParse(stop['latitude'].toString()) ?? 0.0;
          final lng = double.tryParse(stop['longitude'].toString()) ?? 0.0;
          return LatLng(lat, lng);
        }).toList();

        // Check if trip is finished but no path was recorded
        // If path is empty, use start point as the anchor
        if (path.isEmpty) {
          path.add(LatLng(_trip.startLat, _trip.startLng));
        }

        if (mounted) {
          setState(() {
            _trip.path = path;
            if (tripData != null) {
              // Sync notes from multiple possible API keys
              _trip.notes =
                  (tripData['notes']?.toString() ??
                          tripData['visit_notes']?.toString() ??
                          tripData['remarks']?.toString() ??
                          tripData['trip_notes']?.toString() ??
                          _trip.notes)
                      .trim();

              _trip.distanceKm =
                  double.tryParse(tripData['kilometer']?.toString() ?? '') ??
                  double.tryParse(
                    tripData['kilometer_count']?.toString() ?? '',
                  ) ??
                  _trip.distanceKm;
            }
            _isLoading = false;
          });
        }

        // Use actual coordinates if available
        if (path.isNotEmpty) {
          // If only one point exists and trip is COMPLETED, start and end are same
          LatLng actualStart = path.first;
          LatLng actualEnd = path.length > 1 ? path.last : actualStart;
          _reverseGeocodeActualAddresses(actualStart, actualEnd);
        }

        // Fetch official road-wise route using the new API key
        await _fetchRoadWiseRoute(
          path.first,
          path.length > 1 ? path.last : path.first,
          path,
        );
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } else {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _actualStartAddress = "";
  String _actualEndAddress = "";

  Future<void> _reverseGeocodeActualAddresses(LatLng start, LatLng end) async {
    try {
      final startAddr = await _getAddressFromLatLng(start);
      final endAddr = await _getAddressFromLatLng(end);
      if (mounted) {
        setState(() {
          _actualStartAddress = startAddr;
          _actualEndAddress = endAddr;
        });
      }
    } catch (e) {
      debugPrint("Reverse geocoding error: $e");
    }
  }

  Future<void> _startScheduledTrip() async {
    final tp = Provider.of<TripProvider>(context, listen: false);
    final ap = Provider.of<AuthProvider>(context, listen: false);

    if (tp.activeTrip != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "You already have a trip on. Finish your current trip then start this.",
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Attendance guard: must be punched in
    final statusRes = await _attendanceService.getLastPunchStatus(
      ap.user!.systemUserId,
    );
    if (statusRes['success'] == true && (statusRes['isClockedIn'] != true)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please punch in before starting a trip.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    final res = await tp.startScheduledTrip(
      systemUserId: ap.user!.systemUserId,
      tripsId: int.parse(_trip.tripId.toString()),
      tripName: _trip.title,
      fromLocation: _trip.startAddress,
      toLocation: _trip.endAddress,
      lat: _trip.startLat,
      lng: _trip.startLng,
    );

    if (mounted) {
      Navigator.pop(context); // Pop loading
      if (res['success']) {
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/tracking',
          (route) => false,
        );
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(res['message'])));
      }
    }
  }

  Future<String> _getAddressFromLatLng(LatLng position) async {
    try {
      final url = Uri.parse(
        "https://maps.googleapis.com/maps/api/geocode/json?latlng=${position.latitude},${position.longitude}&key=$_googleApiKey",
      );
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK' && data['results'].isNotEmpty) {
          return data['results'][0]['formatted_address'];
        }
      }
    } catch (_) {}
    return "";
  }

  Future<void> _fetchRoadWiseRoute(
    LatLng origin,
    LatLng destination,
    List<LatLng> actualPath,
  ) async {
    try {
      // We use Google Directions API to show the "Ideal" road-wise route
      final url = Uri.parse(
        "https://maps.googleapis.com/maps/api/directions/json"
        "?origin=${origin.latitude},${origin.longitude}"
        "&destination=${destination.latitude},${destination.longitude}"
        "&key=$_googleApiKey",
      );

      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['status'] == 'OK' && data['routes'].isNotEmpty) {
          final route = data['routes'][0];
          final points = route['overview_polyline']['points'];
          final List<LatLng> decodedIdealPoints = _decodePolyline(points);

          if (mounted) {
            setState(() {
              _updateMapWithRoutes(decodedIdealPoints, actualPath);
            });
          }
          return;
        }
      }
      // If API fails, just show the actual path
      if (mounted) _updateMapWithRoutes([], actualPath);
    } catch (e) {
      debugPrint("Error fetching detail route: $e");
      if (mounted) _updateMapWithRoutes([], actualPath);
    }
  }

  void _updateMapWithRoutes(List<LatLng> idealPath, List<LatLng> actualPath) {
    final markers = <Marker>{};

    // Use actual path points for markers
    LatLng startPos = LatLng(_trip.startLat, _trip.startLng);
    LatLng endPos = LatLng(_trip.endLat, _trip.endLng);

    if (actualPath.isNotEmpty) {
      startPos = actualPath.first;
      endPos = actualPath.last;
    } else if (!_trip.isActive) {
      // Completed trip with no stops? End marker should be at start location
      endPos = startPos;
    }

    // Start marker
    markers.add(
      Marker(
        markerId: const MarkerId('start'),
        position: startPos,
        infoWindow: const InfoWindow(title: 'Actual Start Location'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      ),
    );

    // End marker
    markers.add(
      Marker(
        markerId: const MarkerId('end'),
        position: endPos,
        infoWindow: const InfoWindow(title: 'Actual End Location'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      ),
    );

    final polylines = <Polyline>{};

    // 1. Show the "Ideal" road-wise route in light gray (if available)
    if (idealPath.isNotEmpty) {
      polylines.add(
        Polyline(
          polylineId: const PolylineId('ideal_route'),
          points: idealPath,
          color: Colors.black12,
          width: 5,
        ),
      );
    }

    // 2. Show the "Actual" visited path in primary color
    if (actualPath.isNotEmpty) {
      polylines.add(
        Polyline(
          polylineId: const PolylineId('actual_route'),
          points: actualPath,
          color: AppTheme.primaryColor,
          width: 5,
          jointType: JointType.round,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
        ),
      );
    }

    setState(() {
      _markers = markers;
      _polylines = polylines;
    });

    if (_mapController != null) {
      _fitBounds();
    }
  }

  void _fitBounds() {
    List<LatLng> allPoints = [];
    allPoints.add(LatLng(_trip.startLat, _trip.startLng));
    allPoints.add(LatLng(_trip.endLat, _trip.endLng));
    allPoints.addAll(_trip.path);

    if (allPoints.isEmpty) return;

    double minLat = 90.0, maxLat = -90.0, minLng = 180.0, maxLng = -180.0;

    for (var point in allPoints) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }

    // Safety check for degenerate bounds
    if ((maxLat - minLat).abs() < 0.001) {
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(minLat, minLng), 14),
      );
    } else {
      _mapController?.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(minLat, minLng),
            northeast: LatLng(maxLat, maxLng),
          ),
          70,
        ),
      );
    }
  }

  void _finishTrip() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => EndTripDialog(
        distanceKm: _trip.distanceKm,
        durationStr: _formatDuration(
          DateTime.now().difference(_trip.startTime),
        ),
      ),
    );

    if (result != null && mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      final tripProvider = Provider.of<TripProvider>(context, listen: false);
      try {
        final endResp = await tripProvider
            .endTrip(
              _trip.distanceKm,
              _trip.path,
              result['notes'] as String,
              expenseItems: result['expenses'] as List<Map<String, dynamic>>,
            )
            .timeout(const Duration(seconds: 25));

        if (mounted) {
          Navigator.pop(context); // Dismiss loading dialog
          if (endResp['success'] == true) {
            if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
              FlutterBackgroundService().invoke("stopService");
            }
            Provider.of<NotificationProvider>(
              context,
              listen: false,
            ).addNotification("Trip Completed ✅", "You just finished a trip.");
            // Use pushNamedAndRemoveUntil to home to avoid black screen issues
            Navigator.pushNamedAndRemoveUntil(
              context,
              '/home',
              (route) => false,
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  "Error: ${endResp['message'] ?? 'Failed to end trip'}",
                ),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      } catch (e) {
        debugPrint("Error ending trip: $e");
        if (mounted) {
          Navigator.pop(context); // Dismiss loading dialog
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Connection Error: $e"),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  List<LatLng> _decodePolyline(String poly) {
    var list = poly.codeUnits;
    var lList = <double>[];
    int index = 0;
    int len = poly.length;
    int c = 0;
    try {
      do {
        var shift = 0;
        int result = 0;
        do {
          c = list[index] - 63;
          result |= (c & 0x1F) << (shift * 5);
          index++;
          shift++;
        } while (c >= 32);
        if (lList.isEmpty) {
          lList.add(
            ((result & 1) == 1 ? ~(result >> 1) : (result >> 1)) / 100000.0,
          );
        } else {
          lList.add(
            lList.last +
                ((result & 1) == 1 ? ~(result >> 1) : (result >> 1)) / 100000.0,
          );
        }
      } while (index < len);

      List<LatLng> points = [];
      for (var i = 0; i < lList.length; i += 2) {
        points.add(LatLng(lList[i], lList[i + 1]));
      }
      return points;
    } catch (_) {
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          "Trip Summary",
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  flex: 2,
                  child: GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: LatLng(_trip.startLat, _trip.startLng),
                      zoom: 12,
                    ),
                    markers: _markers,
                    polylines: _polylines,
                    onMapCreated: (controller) {
                      _mapController = controller;
                      Future.delayed(
                        const Duration(milliseconds: 600),
                        _fitBounds,
                      );
                    },
                    myLocationEnabled: false,
                    zoomControlsEnabled: false,
                    mapType: MapType.normal,
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(32),
                      ),
                      boxShadow: [
                        BoxShadow(color: Colors.black12, blurRadius: 20),
                      ],
                    ),
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  _trip.title,
                                  style: GoogleFonts.outfit(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              Builder(
                                builder: (context) {
                                  final statusLower = _trip.status
                                      .toLowerCase()
                                      .trim();
                                  String label;
                                  Color bg;
                                  Color fg;

                                  if (statusLower == 'scheduled') {
                                    label = 'SCHEDULED';
                                    bg = Colors.blue[50]!;
                                    fg = Colors.blue[800]!;
                                  } else if (statusLower == 'started' ||
                                      statusLower == 'start' ||
                                      statusLower == 'in progress' ||
                                      statusLower == 'ongoing' ||
                                      _trip.isActive) {
                                    label = 'ACTIVE';
                                    bg = Colors.orange[50]!;
                                    fg = Colors.orange[800]!;
                                  } else {
                                    label = 'COMPLETED';
                                    bg = Colors.green[50]!;
                                    fg = Colors.green[800]!;
                                  }

                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: bg,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      label,
                                      style: GoogleFonts.outfit(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: fg,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (_trip.description.isNotEmpty)
                            Text(
                              _trip.description,
                              style: GoogleFonts.outfit(
                                color: Colors.grey[600],
                                fontSize: 15,
                              ),
                            ),
                          const Divider(height: 40),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _buildStatItem(
                                Icons.calendar_month_outlined,
                                "Date",
                                "${_trip.startTime.day}/${_trip.startTime.month}/${_trip.startTime.year}",
                              ),
                              _buildStatItem(
                                Icons.straighten_rounded,
                                "Distance",
                                "${_trip.distanceKm.toStringAsFixed(2)} km",
                              ),
                            ],
                          ),
                          const SizedBox(height: 40),
                          _buildLocationTimeline(),
                          if (_trip.notes.isNotEmpty) ...[
                            const SizedBox(height: 32),
                            Text(
                              "Visit Summary / Notes",
                              style: GoogleFonts.outfit(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.grey[50],
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.grey[100]!),
                              ),
                              child: Text(
                                _trip.notes,
                                style: GoogleFonts.outfit(
                                  color: Colors.black87,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 80),
                          // Bottom action: for scheduled trips show \"Start Trip\",
                          // for active trips show \"Finish Trip\". Completed trips
                          // have no primary action.
                          if (_trip.status.toLowerCase().trim() ==
                              'scheduled') ...[
                            const SizedBox(height: 24),
                            SizedBox(
                              width: double.infinity,
                              height: 56,
                              child: ElevatedButton(
                                onPressed: widget.canStart
                                    ? _startScheduledTrip
                                    : () {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              "Plan Approval Pending. You can only start trip after plan is approved.",
                                            ),
                                            backgroundColor: Colors.orange,
                                          ),
                                        );
                                      },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: widget.canStart
                                      ? Colors.green
                                      : Colors.grey[400],
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  elevation: 0,
                                ),
                                child: Text(
                                  widget.canStart
                                      ? "Start Trip Now"
                                      : "Approval Pending",
                                  style: GoogleFonts.outfit(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                  ),
                                ),
                              ),
                            ),
                          ] else if (_trip.isActive) ...[
                            const SizedBox(height: 24),
                            SizedBox(
                              width: double.infinity,
                              height: 56,
                              child: ElevatedButton(
                                onPressed: _finishTrip,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.redAccent,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  elevation: 0,
                                ),
                                child: Text(
                                  "Finish Trip Now",
                                  style: GoogleFonts.outfit(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 40),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildStatItem(IconData icon, String label, String value) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppTheme.primaryColor.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: AppTheme.primaryColor, size: 20),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        Text(
          label,
          style: GoogleFonts.outfit(color: Colors.grey, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildLocationTimeline() {
    return Column(
      children: [
        _buildTimelineItem(
          _actualStartAddress.isNotEmpty
              ? _actualStartAddress
              : _trip.startAddress,
          "ACTUAL STARTING POINT",
          Colors.green,
          isFirst: true,
        ),
        const SizedBox(height: 10),
        _buildTimelineItem(
          _actualEndAddress.isNotEmpty
              ? _actualEndAddress
              : (_trip.isActive
                    ? _trip.endAddress
                    : (_actualStartAddress.isNotEmpty
                          ? _actualStartAddress
                          : _trip.startAddress)),
          "ACTUAL END TRIP LOCATION",
          Colors.red,
          isLast: true,
        ),
      ],
    );
  }

  Widget _buildTimelineItem(
    String address,
    String label,
    Color color, {
    bool isFirst = false,
    bool isLast = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 4),
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(color: color.withOpacity(0.3), blurRadius: 6),
                ],
              ),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 40,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [color, Colors.grey[200]!],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.outfit(
                  color: Colors.grey[500],
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                address.isNotEmpty ? address : "Fetching address...",
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    return "${twoDigits(duration.inHours)}:${twoDigits(duration.inMinutes.remainder(60))}:${twoDigits(duration.inSeconds.remainder(60))}";
  }
}
