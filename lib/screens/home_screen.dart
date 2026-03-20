import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:trackersales/providers/auth_provider.dart';
import 'package:trackersales/providers/trip_provider.dart';
import 'package:trackersales/screens/profile_screen.dart';
import 'package:trackersales/screens/trip_detail_screen.dart';
import 'package:trackersales/services/attendance_service.dart';
import 'package:trackersales/services/location_service.dart';
import 'package:intl/intl.dart';

class HomeScreen extends StatefulWidget {
  final VoidCallback? onSeeAll;
  const HomeScreen({super.key, this.onSeeAll});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final AttendanceService _attendanceService = AttendanceService();
  bool _attendanceLoading = true;
  bool _isClockedIn = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAttendanceStatus();
    });
  }

  Future<void> _loadAttendanceStatus() async {
    final ap = Provider.of<AuthProvider>(context, listen: false);
    if (ap.user == null) {
      if (mounted) {
        setState(() {
          _attendanceLoading = false;
          _isClockedIn = false;
        });
      }
      return;
    }

    final result = await _attendanceService.getLastPunchStatus(
      ap.user!.systemUserId,
    );
    if (!mounted) return;
    if (result['success'] == true) {
      setState(() {
        _isClockedIn = result['isClockedIn'] == true;
        _attendanceLoading = false;
      });
    } else {
      setState(() {
        _attendanceLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tripProvider = Provider.of<TripProvider>(context);
    final authProvider = Provider.of<AuthProvider>(context);
    final user = authProvider.user;

    return RefreshIndicator(
      onRefresh: () async {
        final ap = Provider.of<AuthProvider>(context, listen: false);
        final tp = Provider.of<TripProvider>(context, listen: false);
        if (ap.user != null) {
          await tp.fetchTrips(ap.user!.systemUserId);
        }
        await _loadAttendanceStatus();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildUserGreeting(context, user?.name ?? "Rushi"),
                const SizedBox(height: 32),
                if (tripProvider.activeTrip != null) ...[
                  _buildActiveTripCard(context, tripProvider.activeTrip!),
                  const SizedBox(height: 24),
                ] else if (tripProvider.pendingCheckInOut) ...[
                  _PostTripCheckInOutCard(
                    onDismiss: () => tripProvider.dismissCheckInOut(),
                  ),
                  const SizedBox(height: 24),
                ],
                const SizedBox(height: 8),
                _buildRecentTripsHeader(context),
                const SizedBox(height: 16),
                _buildRecentTripsList(context, tripProvider),
              ],
            ),
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          heroTag: 'home_attendance_fab',
          onPressed: () {
            Navigator.pushNamed(context, '/attendance').then((_) {
              // When coming back from Attendance screen, refresh status
              _loadAttendanceStatus();
            });
          },
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          icon: Icon(
            _attendanceLoading
                ? Icons.access_time_rounded
                : _isClockedIn
                ? Icons.logout_rounded
                : Icons.login_rounded,
            size: 24,
          ),
          label: Text(
            _attendanceLoading
                ? 'Attendance'
                : _isClockedIn
                ? 'Punch Out'
                : 'Punch In',
          ),
          elevation: 4,
        ),
      ),
    );
  }

  Widget _buildUserGreeting(BuildContext context, String name) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ProfileScreen()),
                );
              },
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.grey[200]!, width: 1.5),
                ),
                child: CircleAvatar(
                  radius: 18, // Smaller avatar
                  backgroundColor: Colors.grey[100],
                  child: const Icon(
                    Icons.person,
                    color: Colors.black,
                    size: 20,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Hello, $name",
                  style: const TextStyle(
                    fontSize: 16, // Smaller font
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                  ),
                ),
              ],
            ),
          ],
        ),
        GestureDetector(
          onTap: () => Navigator.pushNamed(context, '/notifications'),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.transparent, // Cleaner look
              shape: BoxShape.circle,
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: const Icon(
              Icons.notifications_outlined,
              size: 20,
              color: Colors.black87,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActiveTripCard(BuildContext context, dynamic activeTrip) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Current Trip",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.circle, color: Colors.greenAccent, size: 10),
                    SizedBox(width: 6),
                    Text(
                      "LIVE",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            activeTrip.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(
                Icons.access_time_rounded,
                color: Colors.grey,
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                "Started at ${DateFormat('hh:mm a').format(activeTrip.startTime)}",
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              final tp = Provider.of<TripProvider>(context, listen: false);
              final ap = Provider.of<AuthProvider>(context, listen: false);
              Navigator.pushNamed(context, '/tracking').then((_) {
                if (ap.user != null) {
                  tp.fetchTrips(ap.user!.systemUserId);
                }
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text("Track Journey"),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentTripsHeader(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          "Today's Trips",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        TextButton(onPressed: widget.onSeeAll, child: const Text("See All")),
      ],
    );
  }

  Widget _buildRecentTripsList(BuildContext context, TripProvider provider) {
    final today = DateTime.now();
    final scheduledTrips = provider.trips
        .where(
          (trip) =>
              trip.status.toLowerCase().contains('schedule') &&
              trip.startTime.year == today.year &&
              trip.startTime.month == today.month &&
              trip.startTime.day == today.day &&
              (provider.activeTrip == null ||
                  trip.tripId != provider.activeTrip!.tripId),
        )
        .take(10)
        .toList();

    if (scheduledTrips.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 40),
        width: double.infinity,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.event_note_rounded,
                size: 32,
                color: Colors.grey[300],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              "No trips scheduled for today.",
              style: TextStyle(color: Colors.grey[400]),
            ),
          ],
        ),
      );
    }

    return Column(
      children: scheduledTrips.map((trip) {
        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          child: ListTile(
            onTap: () {
              final ap = Provider.of<AuthProvider>(context, listen: false);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => TripDetailScreen(trip: trip),
                ),
              ).then((_) {
                if (ap.user != null) {
                  provider.fetchTrips(ap.user!.systemUserId);
                }
              });
            },
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.history_rounded,
                color: Colors.black,
                size: 24,
              ),
            ),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  trip.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (trip.description.isNotEmpty)
                  Text(
                    trip.description,
                    style: TextStyle(
                      color: Colors.grey[500],
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.circle, size: 8, color: Colors.green),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        trip.startAddress.isNotEmpty
                            ? trip.startAddress
                            : "Start Point",
                        style: TextStyle(color: Colors.grey[600], fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.circle, size: 8, color: Colors.red),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        trip.endAddress.isNotEmpty
                            ? trip.endAddress
                            : "End Point",
                        style: TextStyle(color: Colors.grey[600], fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  "${DateFormat('dd MMM yyyy').format(trip.startTime)} • ${trip.distanceKm.toStringAsFixed(2)} km",
                  style: TextStyle(color: Colors.grey[500], fontSize: 12),
                ),
              ],
            ),
            trailing: const Icon(
              Icons.chevron_right_rounded,
              color: Colors.grey,
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// Post-Trip Check-In / Check-Out card
// ---------------------------------------------------------------------------

class _PostTripCheckInOutCard extends StatefulWidget {
  final VoidCallback? onDismiss;
  const _PostTripCheckInOutCard({this.onDismiss});

  @override
  State<_PostTripCheckInOutCard> createState() =>
      _PostTripCheckInOutCardState();
}

class _PostTripCheckInOutCardState extends State<_PostTripCheckInOutCard> {
  final AttendanceService _service = AttendanceService();
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _notesController = TextEditingController();

  String? _photoPath;
  bool _checkInDone = false;
  bool _checkOutDone = false;
  bool _loading = false;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    // Location is fetched on demand when an action is triggered
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _capturePhoto() async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 70,
      );
      if (photo != null && mounted) {
        setState(() => _photoPath = photo.path);
      }
    } on PlatformException catch (e) {
      if (!mounted) return;
      String message;
      if (e.code == 'camera_access_denied' ||
          e.code == 'camera_access_denied_without_prompt') {
        message =
            'Camera permission was denied. Open app settings to allow camera if you want to attach photos.';
      } else {
        message = 'Unable to open camera. Please try again.';
      }
      _showMessage(message);
    } catch (_) {
      if (!mounted) return;
      _showMessage('Something went wrong while opening the camera.');
    }
  }

  Future<void> _handleCheckIn() async {
    if (_photoPath == null) {
      _showMessage('Please capture a photo first.');
      return;
    }
    setState(() {
      _loading = true;
      _statusMessage = null;
    });

    try {
      final pos = await LocationService.getCurrentLocation();
      final ap = Provider.of<AuthProvider>(context, listen: false);
      final result = await _service.checkIn(
        systemUserId: ap.user!.systemUserId,
        latitude: pos.latitude,
        longitude: pos.longitude,
        photoPath: _photoPath!,
      );
      if (mounted) {
        setState(() {
          _loading = false;
          _checkInDone = result['success'] == true;
          _statusMessage =
              result['message'] ??
              (result['success'] == true
                  ? 'Checked in successfully.'
                  : 'Check-in failed.');
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _statusMessage = 'Could not get location. Please try again.';
        });
      }
    }
  }

  Future<void> _handleCheckOut() async {
    setState(() {
      _loading = true;
      _statusMessage = null;
    });

    try {
      final pos = await LocationService.getCurrentLocation();
      final ap = Provider.of<AuthProvider>(context, listen: false);
      final result = await _service.checkOut(
        systemUserId: ap.user!.systemUserId,
        latitude: pos.latitude,
        longitude: pos.longitude,
        notes: _notesController.text.trim(),
        photoPath: _photoPath,
      );
      if (mounted) {
        setState(() {
          _loading = false;
          _checkOutDone = result['success'] == true;
          _statusMessage =
              result['message'] ??
              (result['success'] == true
                  ? 'Checked out successfully.'
                  : 'Check-out failed.');
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _statusMessage = 'Could not get location. Please try again.';
        });
      }
    }
  }

  void _showMessage(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bothDone = _checkInDone && _checkOutDone;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.check_circle_outline_rounded,
                      color: Colors.greenAccent,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Trip Completed',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              GestureDetector(
                onTap: widget.onDismiss,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(
                    Icons.close_rounded,
                    color: Colors.white54,
                    size: 16,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 4),
          const Text(
            'Log your visit check-in / check-out',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),

          const SizedBox(height: 16),

          // Photo + notes row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: _loading ? null : _capturePhoto,
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.15),
                      width: 1,
                    ),
                  ),
                  child: _photoPath != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(11),
                          child: Image.file(
                            File(_photoPath!),
                            fit: BoxFit.cover,
                          ),
                        )
                      : const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.camera_alt_rounded,
                              color: Colors.white54,
                              size: 24,
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Photo',
                              style: TextStyle(
                                color: Colors.white38,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
              const SizedBox(width: 12),
              // Notes field – only relevant for Check-Out
              if (_checkInDone && !_checkOutDone)
                Expanded(
                  child: TextField(
                    controller: _notesController,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: 'Check-out notes (optional)',
                      hintStyle: const TextStyle(
                        color: Colors.white38,
                        fontSize: 13,
                      ),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.08),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                )
              else
                Expanded(
                  child: Text(
                    _checkInDone
                        ? 'Checked in. Add notes and check out below.'
                        : 'Capture a photo to check in.\nNotes can be added during check-out.',
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ),
            ],
          ),

          // Status message
          if (_statusMessage != null) ...[
            const SizedBox(height: 10),
            Text(
              _statusMessage!,
              style: TextStyle(
                color: (_checkInDone || _checkOutDone)
                    ? Colors.greenAccent
                    : Colors.redAccent,
                fontSize: 12,
              ),
            ),
          ],

          const SizedBox(height: 14),

          // Action buttons
          if (_loading)
            const Center(
              child: SizedBox(
                height: 36,
                width: 36,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.5,
                ),
              ),
            )
          else if (bothDone)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: widget.onDismiss,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.greenAccent,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text('Done'),
              ),
            )
          else
            Row(
              children: [
                if (!_checkInDone)
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _handleCheckIn,
                      icon: const Icon(Icons.login_rounded, size: 16),
                      label: const Text('Check In'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                if (!_checkInDone && !_checkOutDone) const SizedBox(width: 8),
                if (!_checkOutDone)
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _handleCheckOut,
                      icon: const Icon(Icons.logout_rounded, size: 16),
                      label: const Text('Check Out'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white.withOpacity(0.15),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
              ],
            ),

          // Skip link
          if (!bothDone && !_loading) ...[
            const SizedBox(height: 10),
            Center(
              child: GestureDetector(
                onTap: widget.onDismiss,
                child: const Text(
                  'Skip',
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 12,
                    decoration: TextDecoration.underline,
                    decorationColor: Colors.white38,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
