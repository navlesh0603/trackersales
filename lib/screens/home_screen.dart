import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:trackersales/providers/auth_provider.dart';
import 'package:trackersales/providers/trip_provider.dart';
import 'package:trackersales/screens/trip_detail_screen.dart';
import 'package:trackersales/services/attendance_service.dart';
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
                ],
                if (tripProvider.activeTrip != null) const SizedBox(height: 24),
                const SizedBox(height: 8),
                _buildRecentTripsHeader(context),
                const SizedBox(height: 16),
                _buildRecentTripsList(context, tripProvider),
              ],
            ),
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
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
                // Navigate to profile
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
          "Scheduled Trips",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        TextButton(onPressed: widget.onSeeAll, child: const Text("See All")),
      ],
    );
  }

  Widget _buildRecentTripsList(BuildContext context, TripProvider provider) {
    // Limit for scheduled trips that are NOT currently active at top
    final scheduledTrips = provider.trips
        .where(
          (trip) =>
              trip.status.toLowerCase().contains('schedule') &&
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
              "No scheduled trips found.",
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
