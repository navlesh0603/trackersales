import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:trackersales/providers/trip_provider.dart';
import 'package:trackersales/providers/notification_provider.dart';
import 'package:trackersales/services/location_service.dart';
import 'package:trackersales/theme/app_theme.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:trackersales/utils/constants.dart';
import 'package:trackersales/screens/end_trip_screen.dart';

class TripTrackingScreen extends StatefulWidget {
  const TripTrackingScreen({super.key});

  @override
  State<TripTrackingScreen> createState() => _TripTrackingScreenState();
}

class _TripTrackingScreenState extends State<TripTrackingScreen> {
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  List<LatLng> _pathPoints = [];
  double _totalDistance = 0.0;
  Timer? _durationTimer;
  Duration _tripDuration = Duration.zero;
  StreamSubscription<Position>? _positionSubscription;
  bool _isLoading = true;

  // Direction API Key
  final String _googleApiKey = AppConstants.googleMapsApiKey;

  String _eta = "Calculating...";
  DateTime? _localStartTime;

  @override
  void initState() {
    super.initState();
    _initTracking();
    _startTimers();
  }

  Future<void> _initTracking() async {
    // Failsafe timer: force-stop loading after 5 seconds
    Timer(const Duration(seconds: 5), () {
      if (mounted && _isLoading) {
        setState(() => _isLoading = false);
        debugPrint("Failsafe: Tracking loading timed out, forcing UI to show.");
      }
    });

    try {
      debugPrint("Starting tracking initialization...");
      // Request essential permissions
      await [Permission.location, Permission.notification].request();

      debugPrint("Permissions requested.");

      // For Android 13+, explicitly request notification permission
      if (!kIsWeb && Platform.isAndroid) {
        await Permission.notification.request();
      }

      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        try {
          debugPrint("Starting background service...");
          final service = FlutterBackgroundService();
          bool isRunning = await service.isRunning();
          if (!isRunning) {
            await service.startService();
          }
        } catch (e) {
          debugPrint("Error starting background service: $e");
        }
      }

      debugPrint("Fetching current location...");
      Position? startPos;
      try {
        startPos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
          timeLimit: const Duration(seconds: 4),
        );
      } catch (e) {
        debugPrint("Current position fetch failed: $e. Trying last known.");
        startPos = await Geolocator.getLastKnownPosition();
      }

      // Default fallback if everything fails
      startPos ??= Position(
        latitude: 19.0760,
        longitude: 72.8777,
        timestamp: DateTime.now(),
        accuracy: 0,
        altitude: 0,
        heading: 0,
        speed: 0,
        speedAccuracy: 0,
        altitudeAccuracy: 0,
        headingAccuracy: 0,
      );

      final startLatLng = LatLng(startPos.latitude, startPos.longitude);
      debugPrint("Initial location: $startLatLng");

      if (!mounted) return;
      final tripProvider = Provider.of<TripProvider>(context, listen: false);
      final activeTrip = tripProvider.activeTrip;

      // Persist Timer and Distance
      final prefs = await SharedPreferences.getInstance();
      final storedStart = prefs.getString('active_trip_start_time');
      final storedDist = prefs.getDouble('active_trip_distance') ?? 0.0;
      final storedPath = prefs.getString('active_trip_path');

      if (mounted) {
        setState(() {
          _totalDistance = storedDist;

          if (storedStart != null) {
            try {
              _localStartTime = DateTime.parse(storedStart);
            } catch (_) {
              _localStartTime = activeTrip?.startTime ?? DateTime.now();
            }
          } else if (activeTrip != null) {
            _localStartTime = activeTrip.startTime;
          } else {
            _localStartTime = DateTime.now();
          }

          // Recovery of path points
          if (storedPath != null) {
            try {
              final List<dynamic> decoded = json.decode(storedPath);
              _pathPoints = decoded
                  .map((e) => LatLng(e['lat'] as double, e['lng'] as double))
                  .toList();
            } catch (e) {
              debugPrint("Error decoding stored path: $e");
            }
          }

          if (_pathPoints.isEmpty &&
              activeTrip != null &&
              activeTrip.path.isNotEmpty) {
            _pathPoints = List.from(activeTrip.path);
          }

          if (_pathPoints.isEmpty) {
            _pathPoints.add(startLatLng);
          }

          // Sync with provider's distance if it's significantly higher (server side)
          if (activeTrip != null && activeTrip.distanceKm > _totalDistance) {
            _totalDistance = activeTrip.distanceKm;
          }

          // Ensure markers and polylines are updated with recovered path
          if (_pathPoints.isNotEmpty) {
            _markers.add(
              Marker(
                markerId: const MarkerId("start"),
                position: _pathPoints.first,
                infoWindow: const InfoWindow(title: "Start Point"),
                icon: BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueGreen,
                ),
              ),
            );

            _polylines.add(
              Polyline(
                polylineId: const PolylineId("path"),
                points: List.from(_pathPoints),
                color: AppTheme.primaryColor,
                width: 8,
                jointType: JointType.round,
                startCap: Cap.roundCap,
                endCap: Cap.roundCap,
              ),
            );
          }
        });
        debugPrint(
          "Initialization complete. Distance loaded: $_totalDistance, Points loaded: ${_pathPoints.length}",
        );
      }

      // Listen to Background Service Updates for real-time distance sync
      FlutterBackgroundService().on('update').listen((event) {
        if (!mounted) return;
        if (event != null) {
          bool updated = false;
          final double? bgDistance = event['distance'] != null
              ? double.tryParse(event['distance'].toString())
              : null;

          if (bgDistance != null && bgDistance > _totalDistance) {
            _totalDistance = bgDistance;
            updated = true;
          }

          if (event['path'] != null) {
            try {
              final List<dynamic> pathData = event['path'];
              final List<LatLng> newPath = pathData
                  .map((e) => LatLng(e['lat'] as double, e['lng'] as double))
                  .toList();

              if (newPath.length > _pathPoints.length) {
                _pathPoints = newPath;
                _polylines.removeWhere(
                  (p) => p.polylineId == const PolylineId("path"),
                );
                _polylines.add(
                  Polyline(
                    polylineId: const PolylineId("path"),
                    points: List.from(_pathPoints),
                    color: AppTheme.primaryColor,
                    width: 10, // Slightly thicker for actual path
                    jointType: JointType.round,
                    startCap: Cap.roundCap,
                    endCap: Cap.roundCap,
                  ),
                );
                updated = true;
              }
            } catch (e) {
              debugPrint("Error sync path from BG: $e");
            }
          }

          if (updated) setState(() {});
        }
      });

      if (activeTrip != null && _pathPoints.isNotEmpty) {
        _fetchRoadWiseRoute(
          _pathPoints.first,
          LatLng(activeTrip.endLat, activeTrip.endLng),
        ).catchError((e) => debugPrint("Fetch route error: $e"));
      }

      _positionSubscription = LocationService.getLocationStream().listen((
        Position position,
      ) async {
        try {
          if (!mounted) return;
          final currentLatLng = LatLng(position.latitude, position.longitude);

          // Create custom person icon for current location
          BitmapDescriptor personIcon;
          try {
            personIcon = await _createPersonMarkerIcon();
          } catch (e) {
            debugPrint("Marker icon error: $e");
            personIcon = BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueAzure,
            );
          }

          if (mounted) {
            setState(() {
              _markers.removeWhere(
                (m) => m.markerId == const MarkerId("current"),
              );
              _markers.add(
                Marker(
                  markerId: const MarkerId("current"),
                  position: currentLatLng,
                  anchor: const Offset(0.5, 0.5),
                  infoWindow: const InfoWindow(title: "You (Salesman)"),
                  icon: personIcon,
                  rotation: position.heading,
                ),
              );
            });

            // Note: Distance and Path are now handled by the Background Service listener
            // which Survived app termination and is the source of truth.

            _mapController?.animateCamera(
              CameraUpdate.newLatLngZoom(currentLatLng, 16),
            );
          }
        } catch (e) {
          debugPrint("Error in location listener: $e");
        }
      }, onError: (e) => debugPrint("Location stream error: $e"));
    } catch (e) {
      debugPrint("Severe error in _initTracking: $e");
    } finally {
      if (mounted && _isLoading) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _fetchRoadWiseRoute(LatLng origin, LatLng destination) async {
    try {
      final url = Uri.parse(
        "https://maps.googleapis.com/maps/api/directions/json?origin=${origin.latitude},${origin.longitude}&destination=${destination.latitude},${destination.longitude}&key=$_googleApiKey",
      );
      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['status'] == 'OK' && data['routes'].isNotEmpty) {
          final route = data['routes'][0];
          final points = route['overview_polyline']['points'];
          final duration = route['legs'][0]['duration']['text'];
          final List<LatLng> decodedPoints = _decodePolyline(points);

          if (mounted) {
            setState(() {
              _eta = duration;
              _polylines.removeWhere(
                (p) => p.polylineId == const PolylineId("ideal_route"),
              );
              _polylines.add(
                Polyline(
                  polylineId: const PolylineId("ideal_route"),
                  points: decodedPoints,
                  color: Colors.black12,
                  width: 5,
                ),
              );

              _markers.add(
                Marker(
                  markerId: const MarkerId("destination"),
                  position: destination,
                  infoWindow: InfoWindow(
                    title: "Destination",
                    snippet: "ETA: $duration",
                  ),
                  icon: BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueRed,
                  ),
                ),
              );
            });

            _fitMarkers();
          }
        }
      }
    } catch (e) {
      debugPrint("Error fetching road-wise route: $e");
    }
  }

  void _fitMarkers() {
    if (_mapController == null || _markers.isEmpty) return;

    try {
      double minLat = 90.0, maxLat = -90.0, minLng = 180.0, maxLng = -180.0;

      for (var marker in _markers) {
        if (marker.position.latitude < minLat)
          minLat = marker.position.latitude;
        if (marker.position.latitude > maxLat)
          maxLat = marker.position.latitude;
        if (marker.position.longitude < minLng)
          minLng = marker.position.longitude;
        if (marker.position.longitude > maxLng)
          maxLng = marker.position.longitude;
      }

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
    } catch (e) {
      debugPrint("Error fitting markers: $e");
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

  Future<BitmapDescriptor> _createPersonMarkerIcon() async {
    try {
      // Create a custom person icon with a circular background
      final pictureRecorder = ui.PictureRecorder();
      final canvas = ui.Canvas(pictureRecorder);
      final paint = ui.Paint()..color = AppTheme.primaryColor;

      // Draw circle background
      const double size = 120.0;
      canvas.drawCircle(const Offset(size / 2, size / 2), size / 2, paint);

      // Draw white border
      final borderPaint = ui.Paint()
        ..color = Colors.white
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 8;
      canvas.drawCircle(
        const Offset(size / 2, size / 2),
        size / 2 - 4,
        borderPaint,
      );

      // Draw person icon (simplified)
      final iconPaint = ui.Paint()..color = Colors.white;

      // Head
      canvas.drawCircle(const Offset(size / 2, size / 2 - 15), 15, iconPaint);

      // Body
      final bodyPath = ui.Path();
      bodyPath.moveTo(size / 2, size / 2);
      bodyPath.lineTo(size / 2 - 20, size / 2 + 30);
      bodyPath.lineTo(size / 2 - 15, size / 2 + 30);
      bodyPath.lineTo(size / 2, size / 2 + 5);
      bodyPath.lineTo(size / 2 + 15, size / 2 + 30);
      bodyPath.lineTo(size / 2 + 20, size / 2 + 30);
      bodyPath.close();
      canvas.drawPath(bodyPath, iconPaint);

      final picture = pictureRecorder.endRecording();
      final img = await picture.toImage(size.toInt(), size.toInt());
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      final uint8List = byteData!.buffer.asUint8List();

      return BitmapDescriptor.fromBytes(uint8List);
    } catch (e) {
      debugPrint("Error creating person marker: $e");
      // Fallback to default marker
      return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue);
    }
  }

  void _startTimers() {
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted && _localStartTime != null) {
        setState(() {
          _tripDuration = DateTime.now().difference(_localStartTime!);
        });
      }
    });
  }

  void _finishTrip() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (context) => EndTripScreen(
          distanceKm: _totalDistance,
          durationStr: _formatDuration(_tripDuration),
        ),
        fullscreenDialog: true,
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
        final prefs = await SharedPreferences.getInstance();
        final finalRecordedDistance =
            prefs.getDouble('active_trip_distance') ?? _totalDistance;

        final response = await tripProvider
            .endTrip(
              finalRecordedDistance,
              _pathPoints,
              result['notes'] as String,
              expenseItems: result['expenses'] as List<Map<String, dynamic>>,
            )
            .timeout(const Duration(seconds: 25));

        if (mounted) {
          Navigator.pop(context); // Dismiss loading dialog
          if (response['success'] == true) {
            if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
              FlutterBackgroundService().invoke("stopService");
            }
            Provider.of<NotificationProvider>(
              context,
              listen: false,
            ).addNotification("Trip Completed ✅", "You just finished a trip.");
            // Reset state and stack to home to avoid black screen on some Android versions
            Navigator.pushNamedAndRemoveUntil(
              context,
              '/home',
              (route) => false,
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  "Error: ${response['message'] ?? 'Failed to end trip'}",
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



  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    return "${twoDigits(duration.inHours)}:${twoDigits(duration.inMinutes.remainder(60))}:${twoDigits(duration.inSeconds.remainder(60))}";
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _durationTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          "Active Trip Tracking",
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
        leading: Navigator.canPop(context) 
          ? IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded),
              onPressed: () => Navigator.pop(context),
            )
          : null,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: const CameraPosition(
                    target: LatLng(19.0760, 72.8777),
                    zoom: 15,
                  ),
                  markers: _markers,
                  polylines: _polylines,
                  onMapCreated: (controller) => _mapController = controller,
                  myLocationEnabled: true,
                  myLocationButtonEnabled: true,
                  zoomControlsEnabled: false,
                ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: _buildTrackingStats(),
                ),
              ],
            ),
    );
  }

  Widget _buildTrackingStats() {
    final activeTrip = Provider.of<TripProvider>(context, listen: false).activeTrip;
    
     return Container(
       padding: const EdgeInsets.fromLTRB(24, 24, 24, 80),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(36)),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 25,
            offset: Offset(0, -10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // HIDDEN STATS ROW AS PER REQUEST
          /*
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _statItem(
                "Distance",
                "${_totalDistance.toStringAsFixed(1)} KM",
                Icons.straighten_rounded,
              ),
              _statItem(
                "Duration",
                _formatDuration(_tripDuration),
                Icons.timer_outlined,
              ),
              _statItem("ETA", _eta, Icons.route_rounded),
            ],
          ),
          const SizedBox(height: 32),
          */
          if (activeTrip != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Text(
                activeTrip.title,
                style: GoogleFonts.outfit(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryColor,
                ),
                textAlign: TextAlign.center,
              ),
            ),
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
                "Finish Trip",
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.primaryColor.withOpacity(0.08),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: AppTheme.primaryColor, size: 22),
        ),
        const SizedBox(height: 12),
        Text(
          value,
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: Colors.black,
          ),
        ),
        Text(
          label,
          style: GoogleFonts.outfit(
            color: Colors.grey[500],
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
