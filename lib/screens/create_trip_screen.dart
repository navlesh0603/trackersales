import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:trackersales/models/trip.dart';
import 'package:trackersales/providers/trip_provider.dart';
import 'package:trackersales/providers/auth_provider.dart';
import 'package:trackersales/services/attendance_service.dart';
import 'package:trackersales/screens/location_picker_screen.dart';
import 'package:geolocator/geolocator.dart';
import 'package:trackersales/utils/permission_util.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:trackersales/theme/app_theme.dart';
import 'package:trackersales/utils/constants.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';

class CreateTripScreen extends StatefulWidget {
  final bool isActive;

  /// Opens in "add scheduled trips to this plan" mode (skips creating a new plan).
  final int? existingPlansId;
  final String? existingPlanName;

  /// Plan date from API, usually `dd/MM/yyyy`.
  final String? existingPlanDateStr;

  const CreateTripScreen({
    super.key,
    this.isActive = false,
    this.existingPlansId,
    this.existingPlanName,
    this.existingPlanDateStr,
  });

  bool get isAddingToExistingPlan => existingPlansId != null;

  @override
  State<CreateTripScreen> createState() => _CreateTripScreenState();
}

class _CreateTripScreenState extends State<CreateTripScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  // UI Tabs State
  int _selectedTabIndex = 0; // 0 for Instant Trip, 1 for Schedule Trip

  // --- Instant Trip State ---
  final _instantFormKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _noteController = TextEditingController();
  final _startAddrController = TextEditingController();
  final _endAddrController = TextEditingController();

  LatLng? _endLocation;
  bool _isLoading = false;
  bool _isFetchingCurrentLocation = false;
  bool _locationDetected = false;

  // --- Schedule Trip State ---
  // Plan creation
  bool _isPlanCreated = false;
  final _planFormKey = GlobalKey<FormState>();
  final _planNameController = TextEditingController();
  final _planDescController = TextEditingController();
  DateTime? _planDate;
  bool _planNeedsApproval = true;

  // Trip adding to Plan
  final _schedTripFormKey = GlobalKey<FormState>();
  final _schedFromController = TextEditingController();
  final _schedToController = TextEditingController();
  final _schedRemarkController = TextEditingController();
  List<Map<String, dynamic>> _scheduledTrips = []; // Added trips for the plan

  int? _currentPlanId;
  LatLng? _schedFromLocation;
  LatLng? _schedToLocation;

  final AttendanceService _attendanceService = AttendanceService();

  bool get _addingToExistingPlan => widget.isAddingToExistingPlan;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    if (widget.existingPlansId != null) {
      _selectedTabIndex = 1;
      _currentPlanId = widget.existingPlansId;
      _isPlanCreated = true;
      final name = widget.existingPlanName?.trim();
      if (name != null && name.isNotEmpty) {
        _planNameController.text = name;
      }
      final ds = widget.existingPlanDateStr?.trim();
      if (ds != null && ds.isNotEmpty) {
        try {
          _planDate = DateFormat('dd/MM/yyyy').parseStrict(ds);
        } catch (_) {
          // Other formats: leave _planDate null; UI still works.
        }
      }
    }

    if (widget.isActive) {
      _setInitialLocation();
    }
  }

  @override
  void didUpdateWidget(CreateTripScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      if (!_locationDetected && !_isFetchingCurrentLocation) {
        _setInitialLocation();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        widget.isActive &&
        !_locationDetected &&
        !_isFetchingCurrentLocation) {
      _setInitialLocation();
    }
  }

  Future<void> _setInitialLocation() async {
    if (_isFetchingCurrentLocation) return;
    if (mounted) {
      setState(() {
        _isFetchingCurrentLocation = true;
        _startAddrController.text = "Detecting location...";
      });
    }

    final hasPermissions = await PermissionUtil.checkMandatoryPermissions(
      context,
    );
    if (!hasPermissions) {
      if (mounted) {
        setState(() {
          _isFetchingCurrentLocation = false;
          _startAddrController.text = "";
          _locationDetected = false;
        });
      }
      return;
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );

      final latLng = LatLng(position.latitude, position.longitude);
      final address = await _getAddressFromLatLng(latLng);

      if (mounted) {
        setState(() {
          _startAddrController.text = address;
          _endAddrController.text = address;
          _endLocation = latLng;
          _isFetchingCurrentLocation = false;
          _locationDetected = true;
        });
      }
    } catch (e) {
      debugPrint("Error setting initial location: $e");
      if (mounted) {
        setState(() {
          _isFetchingCurrentLocation = false;
          _locationDetected = false;
          _startAddrController.text = "";
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent[700],
            content: Text(
              "Location detection failed: $e. Try clicking the icon to retry.",
              style: const TextStyle(color: Colors.white),
            ),
            action: SnackBarAction(
              label: "RETRY",
              textColor: Colors.white,
              onPressed: _setInitialLocation,
            ),
          ),
        );
      }
    }
  }

  Future<void> _manualLocationRefresh() async {
    await _setInitialLocation();
  }

  Future<String> _getAddressFromLatLng(LatLng location) async {
    try {
      final apiKey = AppConstants.googleMapsApiKey;
      final url = Uri.parse(
        "https://maps.googleapis.com/maps/api/geocode/json?latlng=${location.latitude},${location.longitude}&key=$apiKey",
      );
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['results'].isNotEmpty) {
          return data['results'][0]['formatted_address'];
        }
      }
    } catch (_) {}
    return "Unknown Location";
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _titleController.dispose();
    _noteController.dispose();
    _startAddrController.dispose();
    _endAddrController.dispose();

    _planNameController.dispose();
    _planDescController.dispose();
    _schedFromController.dispose();
    _schedToController.dispose();
    _schedRemarkController.dispose();
    super.dispose();
  }

  Future<void> _pickEndLocation() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            const LocationPickerScreen(title: "Select End Point"),
      ),
    );

    if (result != null && result is PickedLocation) {
      setState(() {
        _endLocation = result.latLng;
        _endAddrController.text = result.address;
      });
    }
  }

  Future<void> _startInstantTrip() async {
    if (_instantFormKey.currentState!.validate()) {
      final hasPermissions = await PermissionUtil.checkMandatoryPermissions(
        context,
      );
      if (!hasPermissions) return;

      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final user = authProvider.user;

      if (user == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('User not logged in.'),
              backgroundColor: Colors.red,
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

      // Check-in guard: if the user is currently checked in, they must check out first
      final checkInRes = await _attendanceService.getLastCheckInStatus(
        user.systemUserId,
      );
      if (checkInRes['success'] == true && checkInRes['isCheckedIn'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'You are currently checked in. Please check out before starting a new trip.',
              ),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 4),
            ),
          );
        }
        return;
      }

      setState(() => _isLoading = true);

      LatLng liveStartLocation;
      try {
        Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 10),
        );
        liveStartLocation = LatLng(position.latitude, position.longitude);
      } catch (e) {
        setState(() => _isLoading = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to get live location: $e.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final newTrip = Trip(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: _titleController.text.trim(),
        description: "",
        notes: _noteController.text.trim(),
        startAddress: _startAddrController.text.trim(),
        endAddress: _endAddrController.text.trim(),
        startLat: liveStartLocation.latitude,
        startLng: liveStartLocation.longitude,
        endLat: _endLocation?.latitude ?? 0.0,
        endLng: _endLocation?.longitude ?? 0.0,
        startTime: DateTime.now(),
      );

      final tripProvider = Provider.of<TripProvider>(context, listen: false);
      final result = await tripProvider.startTrip(
        systemUserId: user.systemUserId,
        trip: newTrip,
      );

      setState(() => _isLoading = false);

      if (mounted) {
        if (result['success']) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message'] ?? 'Trip started!'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pushReplacementNamed(context, '/tracking');
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message'] ?? 'Failed to start trip'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  // SCHEDULE TRIP METHODS

  Future<void> _pickScheduleLocation(bool isStart) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LocationPickerScreen(
          title: isStart ? "Select From Point" : "Select To Point",
        ),
      ),
    );

    if (result != null && result is PickedLocation) {
      if (mounted) {
        setState(() {
          if (isStart) {
            _schedFromLocation = result.latLng;
            _schedFromController.text = result.address;
          } else {
            _schedToLocation = result.latLng;
            _schedToController.text = result.address;
          }
        });
      }
    }
  }

  void _submitPlan() async {
    if (_planFormKey.currentState!.validate()) {
      if (_planDate == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select a plan date.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      final user = Provider.of<AuthProvider>(context, listen: false).user;
      final tripProvider = Provider.of<TripProvider>(context, listen: false);
      if (user == null) return;

      setState(() => _isLoading = true);

      // Create Plan API
      String dateStr = DateFormat('dd/MM/yyyy').format(_planDate!);
      String appReqStr = _planNeedsApproval ? "Yes" : "No";

      final res = await tripProvider.createPlan(
        systemUserId: user.systemUserId,
        name: _planNameController.text.trim(),
        description: _planDescController.text.trim(),
        date: dateStr,
        approvalRequired: appReqStr,
      );

      setState(() => _isLoading = false);

      if (res['success']) {
        setState(() {
          _currentPlanId = res['plans_id'];
          _isPlanCreated = true;
        });
      } else {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(res['message'])));
        }
      }
    }
  }

  Future<bool> _addScheduledTrip({bool showSuccessToast = true}) async {
    if (_schedTripFormKey.currentState!.validate()) {
      if (_currentPlanId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Plan session expired. Please restart plan creation.',
            ),
          ),
        );
        return false;
      }

      setState(() => _isLoading = true);
      final user = Provider.of<AuthProvider>(context, listen: false).user;
      final tripProvider = Provider.of<TripProvider>(context, listen: false);

      final res = await tripProvider.scheduleTrip(
        systemUserId: user!.systemUserId,
        plansId: _currentPlanId!,
        fromLocation: _schedFromController.text.trim(),
        toLocation: _schedToController.text.trim(),
        remarks: _schedRemarkController.text.trim(),
        fromLat: _schedFromLocation?.latitude ?? 0.0,
        fromLng: _schedFromLocation?.longitude ?? 0.0,
        toLat: _schedToLocation?.latitude ?? 0.0,
        toLng: _schedToLocation?.longitude ?? 0.0,
      );

      setState(() => _isLoading = false);

      if (res['success']) {
        setState(() {
          // Add to local UI list just to show what's added in this session
          _scheduledTrips.add({
            'from': _schedFromController.text.trim(),
            'to': _schedToController.text.trim(),
            'remark': _schedRemarkController.text.trim(),
          });
          _schedFromController.clear();
          _schedToController.clear();
          _schedRemarkController.clear();
          _schedFromLocation = null;
          _schedToLocation = null;
        });
        if (mounted && showSuccessToast) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Trip successfully added to plan!'),
              backgroundColor: Colors.green,
            ),
          );
        }
        return true;
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error adding trip: ${res['message']}'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return false;
      }
    }
    return false;
  }

  /// Close "add to existing plan" flow and let caller refresh.
  Future<void> _finishAddingToExistingPlan() async {
    final hasCurrentDraft =
        _schedFromController.text.trim().isNotEmpty ||
        _schedToController.text.trim().isNotEmpty ||
        _schedRemarkController.text.trim().isNotEmpty ||
        _schedFromLocation != null ||
        _schedToLocation != null;

    if (hasCurrentDraft) {
      final added = await _addScheduledTrip(showSuccessToast: false);
      if (!added) return;
    }

    if (mounted) {
      Navigator.pop(context, true);
    }
  }

  void _finishSubmittingPlan() async {
    final hasCurrentDraft =
        _schedFromController.text.trim().isNotEmpty ||
        _schedToController.text.trim().isNotEmpty ||
        _schedRemarkController.text.trim().isNotEmpty ||
        _schedFromLocation != null ||
        _schedToLocation != null;

    // If user has typed current trip but didn't tap "Add Another",
    // add it automatically before finishing.
    if (hasCurrentDraft) {
      final added = await _addScheduledTrip(showSuccessToast: false);
      if (!added) return;
    }

    if (_scheduledTrips.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add at least one trip before finishing.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    setState(() {
      _isLoading = false;
      _isPlanCreated = false;
      _scheduledTrips.clear();
      _planNameController.clear();
      _planDescController.clear();
      _planDate = null;
      _planNeedsApproval = true;
      _currentPlanId = null;
    });

    if (mounted) {
      // Show success and move to Activity screen (Calendar/Plans)
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Column(
            children: [
              const Icon(
                Icons.check_circle_rounded,
                color: Colors.green,
                size: 60,
              ),
              const SizedBox(height: 16),
              Text(
                "Plan Published",
                style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: const Text(
            "Your trips have been scheduled successfully.",
            textAlign: TextAlign.center,
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  Navigator.pushNamedAndRemoveUntil(
                    context,
                    '/home',
                    (route) => false,
                    arguments: {'initialIndex': 1},
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  "View My Plans",
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _planDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2030),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppTheme.primaryColor,
              onPrimary: Colors.white,
              onSurface: AppTheme.textHeadingColor,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _planDate) {
      setState(() {
        _planDate = picked;
      });
    }
  }

  Widget _buildTabSelector() {
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
            alignment: _selectedTabIndex == 0
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
                _topTabItem(0, "Instant Trip", Icons.bolt_rounded),
                _topTabItem(1, "Schedule Trip", Icons.calendar_today_rounded),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _topTabItem(int index, String label, IconData icon) {
    bool isActive = _selectedTabIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedTabIndex = index),
        child: Container(
          color: Colors.transparent,
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

  Widget _buildInstantTripView() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Form(
        key: _instantFormKey,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              "Where are you going?",
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Start tracking immediately",
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
            const SizedBox(height: 32),
            TextFormField(
              controller: _titleController,
              enabled: !_isLoading,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              decoration: InputDecoration(
                hintText: "Trip Title (e.g., Client Visit)",
                prefixIcon: const Icon(
                  Icons.title_rounded,
                  color: Colors.blueAccent,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 20,
                  horizontal: 16,
                ),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Colors.grey[200]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(
                    color: AppTheme.primaryColor,
                    width: 2,
                  ),
                ),
              ),
              validator: (v) => v!.isEmpty ? "Required" : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _startAddrController,
              readOnly: true,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: _isFetchingCurrentLocation
                    ? "Detecting location..."
                    : "Start Point (Auto-detected)",
                prefixIcon: const Icon(
                  Icons.my_location_rounded,
                  color: Colors.green,
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 20,
                  horizontal: 16,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Colors.grey[200]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(
                    color: AppTheme.primaryColor,
                    width: 2,
                  ),
                ),
                suffixIcon: _isFetchingCurrentLocation
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        icon: const Icon(
                          Icons.refresh_rounded,
                          color: Colors.blue,
                        ),
                        onPressed: _manualLocationRefresh,
                      ),
              ),
              validator: (v) => v!.isEmpty ? "Wait for GPS" : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _endAddrController,
              readOnly: true,
              onTap: _pickEndLocation,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: "Where do you want to go?",
                prefixIcon: const Icon(
                  Icons.location_on_rounded,
                  color: Colors.red,
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 20,
                  horizontal: 16,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Colors.grey[200]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(
                    color: AppTheme.primaryColor,
                    width: 2,
                  ),
                ),
                suffixIcon: const Icon(Icons.map_outlined, color: Colors.grey),
              ),
              validator: (v) => v!.isEmpty ? "Destination required" : null,
            ),
            const SizedBox(height: 48),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _startInstantTrip,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  backgroundColor: AppTheme.primaryColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 4,
                  shadowColor: AppTheme.primaryColor.withOpacity(0.4),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.play_arrow_rounded, size: 28),
                          SizedBox(width: 8),
                          Text(
                            "Start Tracking Now",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSchedulePlanForm() {
    return Form(
      key: _planFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Create New Plan",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            "Setup your schedule details first.",
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
          ),
          const SizedBox(height: 24),
          _buildTextField(
            controller: _planNameController,
            hint: "Plan Name (e.g., Mumbai Tour)",
            icon: Icons.map_rounded,
          ),
          const SizedBox(height: 16),
          _buildTextField(
            controller: _planDescController,
            hint: "Description (Optional)",
            icon: Icons.description_rounded,
            maxLines: 2,
            isRequired: false,
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () => _selectDate(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.calendar_month_rounded,
                    color: Colors.blueAccent,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _planDate == null
                        ? "Select Plan Date"
                        : "${_planDate!.day}/${_planDate!.month}/${_planDate!.year}",
                    style: TextStyle(
                      fontSize: 16,
                      color: _planDate == null
                          ? Colors.grey[600]
                          : Colors.black87,
                      fontWeight: _planDate == null
                          ? FontWeight.normal
                          : FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  const Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 16,
                    color: Colors.grey,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.verified_user_rounded,
                      color: Colors.orangeAccent,
                    ),
                    SizedBox(width: 12),
                    Text(
                      "Needs Approval?",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                Switch.adaptive(
                  value: _planNeedsApproval,
                  activeColor: AppTheme.primaryColor,
                  onChanged: (val) {
                    setState(() {
                      _planNeedsApproval = val;
                    });
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _submitPlan,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      "Next: Add Trips",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleAddTripsView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header Card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.blueGrey[50],
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.blueGrey[100]!),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _planNameController.text.isNotEmpty
                              ? _planNameController.text
                              : "Upcoming Plan",
                          style: GoogleFonts.outfit(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (_currentPlanId != null)
                          Container(
                            margin: const EdgeInsets.only(top: 4),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              "PLAN ID: $_currentPlanId",
                              style: GoogleFonts.outfit(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.blueGrey,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (!_addingToExistingPlan)
                    GestureDetector(
                      onTap: () => setState(() => _isPlanCreated = false),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.edit_rounded,
                          size: 18,
                          color: Colors.blue,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                _planDate != null
                    ? "Date: ${_planDate!.day}/${_planDate!.month}/${_planDate!.year}"
                    : "",
                style: TextStyle(fontSize: 14, color: Colors.grey[700]),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Added Trips List
        if (_scheduledTrips.isNotEmpty) ...[
          const Text(
            "Added Trips",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _scheduledTrips.length,
            itemBuilder: (ctx, idx) {
              final trip = _scheduledTrips[idx];
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 15,
                      offset: const Offset(0, 5),
                    ),
                  ],
                  border: Border.all(color: Colors.grey[100]!),
                ),
                child: Row(
                  children: [
                    Column(
                      children: [
                        const Icon(Icons.circle, size: 8, color: Colors.green),
                        Container(
                          height: 20,
                          width: 1,
                          color: Colors.grey[200],
                        ),
                        const Icon(Icons.square, size: 8, color: Colors.black),
                      ],
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "From: ${trip['from'] ?? ""}",
                            style: GoogleFonts.outfit(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Colors.grey[800],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            "To: ${trip['to'] ?? ""}",
                            style: GoogleFonts.outfit(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Colors.grey[800],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.check_circle_rounded,
                      color: Colors.green,
                      size: 20,
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 16),
        ],

        // Add Trip Form
        Form(
          key: _schedTripFormKey,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.grey[200]!),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.02),
                  blurRadius: 10,
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Add Location",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[800],
                  ),
                ),
                const SizedBox(height: 16),
                _buildRouteLocationField(
                  controller: _schedFromController,
                  hint: "From Location",
                  isStart: true,
                ),
                const SizedBox(height: 16),
                _buildRouteLocationField(
                  controller: _schedToController,
                  hint: "To Location",
                  isStart: false,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _schedRemarkController,
                  decoration: InputDecoration(
                    hintText: "Remark (if any)",
                    prefixIcon: const Icon(
                      Icons.chat_bubble_outline_rounded,
                      size: 20,
                    ),
                    filled: true,
                    fillColor: Colors.grey[50],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 32),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _isLoading
                    ? null
                    : () async {
                        await _addScheduledTrip();
                      },
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  side: const BorderSide(color: AppTheme.primaryColor),
                ),
                child: Text(
                  _addingToExistingPlan ? "Add trip" : "Add Another",
                  style: const TextStyle(
                    color: AppTheme.primaryColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: ElevatedButton(
                onPressed: _isLoading
                    ? null
                    : (_addingToExistingPlan
                          ? _finishAddingToExistingPlan
                          : _finishSubmittingPlan),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        _addingToExistingPlan ? "Done" : "Submit Plan",
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 48),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    int maxLines = 1,
    bool isRequired = true,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, color: Colors.grey[600]),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          vertical: 16,
          horizontal: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.grey[200]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppTheme.primaryColor, width: 2),
        ),
      ),
      validator: isRequired ? (v) => v!.isEmpty ? "Required" : null : null,
    );
  }

  Widget _buildRouteLocationField({
    required TextEditingController controller,
    required String hint,
    required bool isStart,
  }) {
    return Row(
      children: [
        Container(
          width: 30,
          alignment: Alignment.center,
          child: Icon(
            isStart ? Icons.circle : Icons.square,
            size: isStart ? 14 : 14,
            color: isStart ? Colors.green : Colors.black,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextFormField(
            controller: controller,
            readOnly: true,
            onTap: () => _pickScheduleLocation(isStart),
            decoration: InputDecoration(
              hintText: hint,
              suffixIcon: const Icon(
                Icons.location_on_rounded,
                color: Colors.blueAccent,
              ),
              filled: true,
              fillColor: Colors.grey[50],
              contentPadding: const EdgeInsets.symmetric(
                vertical: 14,
                horizontal: 16,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey[200]!),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.primaryColor),
              ),
            ),
            validator: (v) => v!.isEmpty ? "Required" : null,
          ),
        ),
      ],
    );
  }

  Widget _buildScheduleTripView() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: _isPlanCreated
            ? _buildScheduleAddTripsView()
            : _buildSchedulePlanForm(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          Colors.grey[50], // Slightly off-white background for Uber look
      appBar: AppBar(
        title: Text(
          _addingToExistingPlan ? "Add trip to plan" : "Create Trip",
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18),
        ),
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
      body: SafeArea(
        child: Column(
          children: [
            if (!_addingToExistingPlan) _buildTabSelector(),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: _selectedTabIndex == 0
                            ? Center(child: _buildInstantTripView())
                            : Center(child: _buildScheduleTripView()),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
