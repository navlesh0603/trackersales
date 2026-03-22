import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:trackersales/providers/auth_provider.dart';
import 'package:trackersales/providers/trip_provider.dart';
import 'package:trackersales/models/trip.dart';
import 'package:trackersales/screens/plan_trips_screen.dart';
import 'package:trackersales/screens/trip_detail_screen.dart';
import 'package:trackersales/theme/app_theme.dart';
import 'package:trackersales/services/attendance_service.dart';

class FutureTripsScreen extends StatefulWidget {
  const FutureTripsScreen({super.key});

  @override
  State<FutureTripsScreen> createState() => _FutureTripsScreenState();
}

class _FutureTripsScreenState extends State<FutureTripsScreen> {
  // Calendar State
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  // Tab State
  int _activeTabIndex = 0; // 0 for Calendar, 1 for Plans

  // Plans State
  List<dynamic> _plans = [];
  bool _isLoadingPlans = false;
  int? _expandedPlanId;
  Map<int, List<dynamic>> _planTrips = {};

  final AttendanceService _attendanceService = AttendanceService();

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchCalendarTrips();
      _fetchPlans();
    });
  }

  Future<void> _fetchCalendarTrips() async {
    final user = Provider.of<AuthProvider>(context, listen: false).user;
    if (user != null) {
      await Provider.of<TripProvider>(
        context,
        listen: false,
      ).fetchTrips(user.systemUserId);
    }
  }

  Future<void> _fetchPlans() async {
    final user = Provider.of<AuthProvider>(context, listen: false).user;
    if (user == null) return;

    setState(() => _isLoadingPlans = true);
    final result = await Provider.of<TripProvider>(
      context,
      listen: false,
    ).getPlans(user.systemUserId);
    if (mounted) {
      setState(() {
        if (result['success']) {
          _plans = List.from(result['data'].reversed);
        }
        _isLoadingPlans = false;
      });
    }
  }

  Future<void> _fetchTripsByPlan(int plansId) async {
    if (_planTrips.containsKey(plansId)) return;

    final user = Provider.of<AuthProvider>(context, listen: false).user;
    if (user == null) return;

    final result = await Provider.of<TripProvider>(
      context,
      listen: false,
    ).getTripsByPlan(user.systemUserId, plansId);
    if (mounted && result['success']) {
      setState(() {
        _planTrips[plansId] = List.from(result['data'].reversed);
      });
    }
  }

  void _startTrip(dynamic trip) async {
    final user = Provider.of<AuthProvider>(context, listen: false).user;
    final tripProvider = Provider.of<TripProvider>(context, listen: false);
    if (user == null) return;

    if (tripProvider.activeTrip != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'You already have a trip on. Finish your current trip then start this.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    // Attendance guard: must be punched in
    final statusRes = await _attendanceService.getLastPunchStatus(
      user.systemUserId,
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

    final res = await tripProvider.startScheduledTrip(
      systemUserId: user.systemUserId,
      tripsId: int.parse(trip['trips_id'].toString()),
      tripName: trip['plan_name'] ?? trip['trip_name'] ?? "Scheduled Trip",
      fromLocation: trip['from_location'] ?? "Unknown",
      toLocation: trip['to_location'] ?? "Unknown",
      lat: double.tryParse(trip['from_location_latitude'].toString()) ?? 0.0,
      lng: double.tryParse(trip['from_location_longitude'].toString()) ?? 0.0,
    );

    if (mounted) {
      Navigator.pop(context); // Pop loading
      if (res['success']) {
        if (mounted) {
          Navigator.pushNamed(context, '/tracking');
        }
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(res['message'])));
      }
    }
  }

  List<dynamic> _getCalendarEvents(DateTime day, List<Trip> historyTrips) {
    List<dynamic> items = <dynamic>[];

    // Get plans for this day
    final dayStr = DateFormat('dd/MM/yyyy').format(day);
    final dayPlans = _plans.where((p) => p['date'] == dayStr).toList();

    for (var plan in dayPlans) {
      items.add({
        ...plan,
        'isPlan': true,
        'plan_id': plan['plans_id'], // Ensuring plan_id is also there
        // Use backend "status" field directly (NEW / APPROVED / NOT REQUIRED)
        'status': (plan['status'] ?? '').toString(),
      });
    }

    return items;
  }

  @override
  Widget build(BuildContext context) {
    final tripProvider = Provider.of<TripProvider>(context);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          "Trip Planner",
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 22),
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
      body: Column(
        children: [
          _buildTabSwitcher(),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _activeTabIndex == 0
                  ? Center(child: _buildCalendarView(tripProvider))
                  : Center(child: _buildPlansView()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabSwitcher() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      padding: const EdgeInsets.all(4),
      height: 56,
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(20),
      ),
      child: Stack(
        children: [
          AnimatedAlign(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOutExpo,
            alignment: _activeTabIndex == 0
                ? Alignment.centerLeft
                : Alignment.centerRight,
            child: FractionallySizedBox(
              widthFactor: 0.5,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Row(
              children: [
                _switcherTab(0, "Calendar", Icons.calendar_today_rounded),
                _switcherTab(1, "Scheduled Plans", Icons.event_note_rounded),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _switcherTab(int index, String label, IconData icon) {
    bool isActive = _activeTabIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _activeTabIndex = index),
        child: Container(
          color: Colors.transparent, // Capture taps
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: isActive ? Colors.black : Colors.grey[500],
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: GoogleFonts.outfit(
                  color: isActive ? Colors.black : Colors.grey[500],
                  fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCalendarView(TripProvider tripProvider) {
    final activities = _getCalendarEvents(
      _selectedDay ?? _focusedDay,
      tripProvider.trips,
    );
    return Column(
      key: const ValueKey(0),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.grey[100]!),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.02),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: TableCalendar<dynamic>(
            firstDay: DateTime.now().subtract(const Duration(days: 365)),
            lastDay: DateTime.now().add(const Duration(days: 365)),
            focusedDay: _focusedDay,
            calendarFormat: _calendarFormat,
            rowHeight: 44,
            headerStyle: HeaderStyle(
              formatButtonVisible: false,
              titleCentered: true,
              titleTextStyle: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            calendarStyle: CalendarStyle(
              selectedDecoration: const BoxDecoration(
                color: Colors.black,
                shape: BoxShape.circle,
              ),
              todayDecoration: BoxDecoration(
                color: Colors.grey[200],
                shape: BoxShape.circle,
              ),
              defaultTextStyle: GoogleFonts.outfit(),
              weekendTextStyle: GoogleFonts.outfit(color: Colors.red[300]),
            ),
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            onDaySelected: (selectedDay, focusedDay) {
              setState(() {
                _selectedDay = selectedDay;
                _focusedDay = focusedDay;
              });
            },
            eventLoader: (day) => _getCalendarEvents(day, tripProvider.trips),
          ),
        ),
        if (activities.isNotEmpty)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: ListView.builder(
                padding: const EdgeInsets.only(top: 16, bottom: 80),
                itemCount: activities.length,
                itemBuilder: (context, index) {
                  final item = activities[index];
                  if (item is Trip) {
                    return _tripItem(context, item);
                  } else {
                    return _planSummaryItem(item);
                  }
                },
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: _buildEmptyState("No activities for this day"),
          ),
      ],
    );
  }

  Widget _buildPlansView() {
    return Column(
      key: const ValueKey(1),
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: _fetchPlans,
            child: _isLoadingPlans
                ? const Center(child: CircularProgressIndicator())
                : _plans.isEmpty
                ? _buildEmptyState("You haven't created any plans yet.")
                : ListView.builder(
                    padding: const EdgeInsets.all(24),
                    itemCount: _plans.length,
                    itemBuilder: (context, index) =>
                        _buildPlanCard(_plans[index]),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildPlanCard(dynamic plan) {
    final String rawStatus = (plan['status'] ?? '').toString().toUpperCase();
    final bool needsApp = plan['approval_required'] == "Yes";

    // Consider NOT REQUIRED effectively "approved" from a start‑permission POV.
    final bool isApproved =
        rawStatus == "APPROVED" || rawStatus == "NOT REQUIRED";

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey[100]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => PlanTripsScreen(
                  plan: {
                    ...plan,
                    // Pass through the backend status string ("NEW", "APPROVED", etc.)
                    'status': plan['status'],
                  },
                ),
              ),
            );
          },
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        plan['name'] ?? "Untitled Plan",
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    _statusBadge(
                      needsApp
                          ? (isApproved ? "Approved" : "Pending Approval")
                          : "Scheduled",
                      needsApp
                          ? (isApproved ? Colors.green : Colors.orange)
                          : Colors.blue,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today_rounded,
                      size: 14,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(width: 6),
                    Text(
                      plan['date'] ?? "No Date",
                      style: GoogleFonts.outfit(
                        color: Colors.grey[500],
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                if (plan['description'] != null &&
                    plan['description'].toString().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    plan['description'],
                    style: GoogleFonts.outfit(
                      color: Colors.grey[400],
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const Divider(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "View Plan Trips",
                      style: GoogleFonts.outfit(
                        color: Colors.blue,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 12,
                      color: Colors.blue,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlanTripsList(int planId) {
    if (!_planTrips.containsKey(planId)) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    final trips = _planTrips[planId]!;
    if (trips.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Text(
          "No trips added to this plan",
          style: GoogleFonts.outfit(color: Colors.grey[400], fontSize: 13),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: trips.length,
      itemBuilder: (context, index) {
        final trip = trips[index];
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            children: [
              Column(
                children: [
                  const Icon(Icons.circle, size: 10, color: Colors.green),
                  Container(width: 1.5, height: 20, color: Colors.grey[200]),
                  const Icon(Icons.square, size: 10, color: Colors.black),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      trip['from_location'] ?? "From",
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      trip['to_location'] ?? "To",
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (trip['purpose_of_visit'] != null &&
                        trip['purpose_of_visit'].toString().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        "Purpose: ${trip['purpose_of_visit']}",
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          color: Colors.blueGrey,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    if (trip['notes'] != null &&
                        trip['notes'].toString().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        "Notes: ${trip['notes']}",
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trip['trip_status'] == "Scheduled")
                ElevatedButton(
                  onPressed: () => _startTrip(trip),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    minimumSize: const Size(0, 32),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    "Start",
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                )
              else
                _statusBadge(
                  trip['trip_status'],
                  _getStatusColor(trip['trip_status']),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _planSummaryItem(dynamic plan) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey[100]!),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.orange[50],
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.event_note_rounded,
              color: Colors.orange[400],
              size: 20,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  plan['name'] ?? "Plan",
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                Text(
                  plan['description'] ?? "No description",
                  style: GoogleFonts.outfit(
                    color: Colors.grey[500],
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => PlanTripsScreen(plan: plan),
                ),
              );
            },
            child: const Text("View Trips"),
          ),
        ],
      ),
    );
  }

  Widget _statusBadge(String status, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        status,
        style: GoogleFonts.outfit(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case "Started":
        return Colors.blue;
      case "Completed":
        return Colors.green;
      case "Scheduled":
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.event_busy_rounded, size: 64, color: Colors.grey[100]),
          const SizedBox(height: 16),
          Text(
            message,
            style: GoogleFonts.outfit(color: Colors.grey[400], fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _tripItem(BuildContext context, Trip trip) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => TripDetailScreen(trip: trip)),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey[100]!),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    trip.title,
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: Colors.black87,
                    ),
                    maxLines: 1,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    trip.startAddress.isNotEmpty
                        ? trip.startAddress
                        : "Location not set",
                    style: GoogleFonts.outfit(
                      color: Colors.grey[500],
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: Colors.grey[300]),
          ],
        ),
      ),
    );
  }
}
