import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:trackersales/providers/auth_provider.dart';
import 'package:trackersales/providers/trip_provider.dart';
import 'package:trackersales/screens/trip_detail_screen.dart';
import 'package:trackersales/services/attendance_service.dart';
import 'package:trackersales/models/trip.dart';
import 'package:trackersales/screens/create_trip_screen.dart';
import 'package:intl/intl.dart';

class PlanTripsScreen extends StatefulWidget {
  final Map<dynamic, dynamic> plan;

  const PlanTripsScreen({super.key, required this.plan});

  @override
  State<PlanTripsScreen> createState() => _PlanTripsScreenState();
}

class _PlanTripsScreenState extends State<PlanTripsScreen> {
  List<dynamic> _trips = [];
  bool _isLoading = true;
  bool _isSubmittingApproval = false;
  bool _locallySubmittedForApproval = false;
  String? _latestPlanStatus;
  final AttendanceService _attendanceService = AttendanceService();

  @override
  void initState() {
    super.initState();
    _fetchTrips();
  }

  /// Plan trips use the plan's date; only today or future plans accept new trips.
  bool _planDateIsTodayOrFuture() {
    final raw = widget.plan['date']?.toString();
    if (raw == null || raw.isEmpty) return true;
    try {
      final d = DateFormat('dd/MM/yyyy').parseStrict(raw.trim());
      final today = DateTime.now();
      final planDay = DateTime(d.year, d.month, d.day);
      final todayDay = DateTime(today.year, today.month, today.day);
      return !planDay.isBefore(todayDay);
    } catch (_) {
      return true;
    }
  }

  Future<void> _openAddTripToPlan() async {
    if (!_planDateIsTodayOrFuture()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'You can only add trips to plans dated today or in the future.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    final statusUpper =
        (_latestPlanStatus ??
                widget.plan['status'] ??
                widget.plan['approval_approved'] ??
                '')
            .toString()
            .toUpperCase()
            .trim();
    if (statusUpper != 'NEW') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              statusUpper.isEmpty
                  ? 'Unable to verify plan status. Pull to refresh and try again.'
                  : 'Trips can only be added while the plan status is NEW. '
                        'This plan is $statusUpper — adding trips is not allowed.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    final rawId = widget.plan['plan_id'] ?? widget.plan['plans_id'];
    final planId = int.tryParse(rawId?.toString() ?? '0') ?? 0;
    if (planId == 0) return;

    final name = (widget.plan['name'] ?? widget.plan['plan_name'] ?? 'Plan')
        .toString();
    final dateStr = widget.plan['date']?.toString();

    final added = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => CreateTripScreen(
          existingPlansId: planId,
          existingPlanName: name,
          existingPlanDateStr: dateStr,
        ),
      ),
    );

    if (added == true && mounted) {
      setState(() => _isLoading = true);
      await _fetchTrips();
    }
  }

  Future<void> _fetchTrips() async {
    final user = Provider.of<AuthProvider>(context, listen: false).user;
    if (user == null) return;

    if (mounted) setState(() => _isLoading = true);

    try {
      final rawId = widget.plan['plan_id'] ?? widget.plan['plans_id'];
      debugPrint(
        "Fetching trips for plan: ${widget.plan['name']} with ID: $rawId",
      );

      final int planId = int.parse(rawId?.toString() ?? '0');

      if (planId == 0) {
        debugPrint("Warning: Plan ID is 0");
      }

      final result = await Provider.of<TripProvider>(
        context,
        listen: false,
      ).getTripsByPlan(user.systemUserId, planId);
      final plansResult = await Provider.of<TripProvider>(
        context,
        listen: false,
      ).getPlans(user.systemUserId);

      debugPrint("API Result for getTripsByPlan: $result");

      if (mounted) {
        setState(() {
          if (result['success'] && result['data'] != null) {
            _trips = List.from(result['data'].reversed);
            debugPrint(
              "Successfully loaded ${_trips.length} trips into _trips list",
            );
            if (_trips.isNotEmpty) {
              debugPrint("First trip data: ${_trips.first}");
            }
          }

          // Refresh plan status from latest plans API to avoid stale
          // status passed via widget.plan.
          if (plansResult['success'] == true && plansResult['data'] is List) {
            final currentPlan = (plansResult['data'] as List)
                .cast<dynamic>()
                .whereType<Map>()
                .cast<Map<dynamic, dynamic>>()
                .firstWhere(
                  (p) =>
                      (p['plans_id']?.toString() ?? p['plan_id']?.toString()) ==
                      planId.toString(),
                  orElse: () => {},
                );
            if (currentPlan.isNotEmpty) {
              _latestPlanStatus = (currentPlan['status'] ?? '').toString();
            }
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching plan trips: $e");
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _handleTripClick(dynamic tripData, bool canStart) {
    // Convert API map to Trip object or navigate to detail with data
    // Since TripDetailScreen expects a Trip object, we might need to fetch full history
    // or convert this map.

    // Check if this trip exists in provider's trips (which are full Trip objects)
    final provider = Provider.of<TripProvider>(context, listen: false);
    final existingTrip = provider.trips.cast<Trip?>().firstWhere(
      (t) => t?.tripId == tripData['trips_id'].toString(),
      orElse: () => null,
    );

    if (existingTrip != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) =>
              TripDetailScreen(trip: existingTrip, canStart: canStart),
        ),
      );
    } else {
      // Create a temporary Trip object from tripData
      final tempTrip = Trip.fromJson(tripData);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) =>
              TripDetailScreen(trip: tempTrip, canStart: canStart),
        ),
      );
    }
  }

  void _startTrip(dynamic trip) async {
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
        Navigator.pop(context); // Pop this screen
        Navigator.pushNamed(context, '/tracking');
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(res['message'])));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final planStatus =
        (_latestPlanStatus ??
                widget.plan['status'] ??
                widget.plan['approval_approved'] ??
                '')
            .toString();
    final upperStatus = planStatus.toUpperCase();
    final needsApp =
        (widget.plan['approval_required'] ?? '').toString() == "Yes";

    // Backend status values: "NEW", "SUBMITTED", "APPROVED", "NOT REQUIRED".
    final bool isApproved = upperStatus == "APPROVED";
    // Both APPROVED and NOT REQUIRED allow starting trips.
    final bool canStart = isApproved || upperStatus == "NOT REQUIRED";
    // Only truly NEW (not yet submitted) plans show the submit button.
    final bool isNew = upperStatus == "NEW";
    final bool showSubmitButton =
        !_isLoading &&
        needsApp &&
        isNew &&
        upperStatus != "SUBMITTED" &&
        !_locallySubmittedForApproval;
    // Add trips only for NEW plans (not approved / submitted / etc.) and valid plan date.
    final bool canAddTrips = _planDateIsTodayOrFuture() && isNew;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          (widget.plan['name'] ?? widget.plan['plan_name'] ?? "Plan Trips")
              .toString(),
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
        actions: [
          if (canAddTrips)
            Padding(
              padding: const EdgeInsets.only(right: 8, top: 6, bottom: 6),
              child: FilledButton.icon(
                onPressed: _isLoading ? null : _openAddTripToPlan,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(
                  'Add trip',
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _fetchTrips,
          child: _isLoading
              ? _buildScrollableLoading()
              : _trips.isEmpty
              ? _buildScrollableEmpty(canAddTrips)
              : ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 24,
                  ),
                  itemCount: _trips.length,
                  itemBuilder: (context, index) {
                    try {
                      final trip = _trips[index];
                      if (trip == null || trip is! Map) {
                        return const SizedBox();
                      }
                      return _buildTripCard(trip, canStart, planStatus);
                    } catch (e) {
                      debugPrint(
                        "Error building trip card at index $index: $e",
                      );
                      return const SizedBox();
                    }
                  },
                ),
        ),
      ),
      bottomNavigationBar: showSubmitButton
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _isSubmittingApproval
                        ? null
                        : _submitPlanForApproval,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    icon: _isSubmittingApproval
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.verified_outlined, size: 20),
                    label: Text(
                      _isSubmittingApproval
                          ? "Submitting..."
                          : "Submit Plan for Approval",
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            )
          : null,
    );
  }

  Future<void> _submitPlanForApproval() async {
    final user = Provider.of<AuthProvider>(context, listen: false).user;
    if (user == null) return;

    final rawId = widget.plan['plan_id'] ?? widget.plan['plans_id'];
    final int planId = int.parse(rawId?.toString() ?? '0');
    if (planId == 0) return;

    setState(() {
      _isSubmittingApproval = true;
    });

    try {
      final tripProvider = Provider.of<TripProvider>(context, listen: false);
      final res = await tripProvider.submitPlanForApproval(
        systemUserId: user.systemUserId,
        plansId: planId,
      );

      if (!mounted) return;

      if (res['success'] == true) {
        setState(() {
          _locallySubmittedForApproval = true;
          _latestPlanStatus = 'SUBMITTED';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Plan submitted for approval.'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              res['message']?.toString() ??
                  'Failed to submit plan for approval',
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error submitting plan: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmittingApproval = false;
        });
      }
    }
  }

  Widget _buildScrollableLoading() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: const Center(child: CircularProgressIndicator()),
        ),
      ],
    );
  }

  Widget _buildScrollableEmpty(bool canAddTrips) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.map_outlined, size: 64, color: Colors.grey[200]),
              const SizedBox(height: 16),
              Text(
                "No trips found in this plan",
                style: GoogleFonts.outfit(
                  color: Colors.grey[400],
                  fontSize: 16,
                ),
              ),
              if (canAddTrips) ...[
                const SizedBox(height: 28),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _openAddTripToPlan,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      icon: const Icon(Icons.add_road_rounded, size: 22),
                      label: Text(
                        'Add trip',
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ),
              ] else ...[
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    !_planDateIsTodayOrFuture()
                        ? 'This plan’s date is in the past. New trips can only be added to today’s or future plans.'
                        : 'Trips can only be added while the plan status is NEW. Once the plan is approved, submitted, or no longer NEW, you cannot add trips here.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      color: Colors.grey[500],
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTripCard(dynamic trip, bool canStart, String planStatus) {
    if (trip == null) return const SizedBox();

    final tripStatus = (trip['trip_status'] ?? '').toString();
    bool isScheduled = tripStatus == "Scheduled";

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _handleTripClick(trip, canStart),
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.route_rounded,
                        color: Colors.blue,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (trip['trip_name'] ?? trip['plan_name'] ?? "Trip")
                                .toString(),
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            tripStatus.isEmpty ? "Pending" : tripStatus,
                            style: GoogleFonts.outfit(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isScheduled) ...[
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: canStart ? () => _startTrip(trip) : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: canStart
                              ? Colors.green
                              : Colors.grey[300],
                          foregroundColor: canStart
                              ? Colors.white
                              : Colors.grey[600],
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          minimumSize: const Size(0, 36),
                        ),
                        child: Text(
                          canStart
                              ? "Start"
                              : (planStatus == "Pending" || planStatus == "0")
                              ? "Pending"
                              : "Needs Approval",
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Divider(height: 1),
                ),
                _locationRow(
                  Icons.my_location,
                  (trip['from_location'] ?? "Start").toString(),
                  Colors.green,
                ),
                const SizedBox(height: 12),
                _locationRow(
                  Icons.location_on,
                  (trip['to_location'] ?? "Destination").toString(),
                  Colors.red,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _locationRow(IconData icon, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.max,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.outfit(fontSize: 13, color: Colors.grey[700]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
