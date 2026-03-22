import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:trackersales/providers/auth_provider.dart';
import 'package:trackersales/services/attendance_service.dart';
import 'package:trackersales/services/location_service.dart';

/// Visit check-in / check-out — same flow pattern as Punch In / Punch Out.
/// Uses [AttendanceService.getLastCheckInStatus] so state survives leaving the screen.
class CheckInOutScreen extends StatefulWidget {
  const CheckInOutScreen({super.key});

  @override
  State<CheckInOutScreen> createState() => _CheckInOutScreenState();
}

class _CheckInOutScreenState extends State<CheckInOutScreen> {
  final AttendanceService _service = AttendanceService();
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _notesController = TextEditingController();

  bool _pageLoading = true;
  bool _checkedIn = false;
  /// Must be punched in (attendance) before visit check-in is allowed.
  bool _isPunchedIn = false;
  String _checkInTimeLabel = '';
  String _checkInDateLabel = '';

  String _currentTime = '';
  String _currentDate = '';

  String? _checkInPhotoPath;
  String? _checkOutPhotoPath;

  String _locationAddress = '';
  double? _latitude;
  double? _longitude;
  bool _isLoadingLocation = true;
  bool _locationError = false;

  bool _isCheckingIn = false;
  bool _isCheckingOut = false;
  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();
    _notesController.addListener(_onNotesChanged);
    _updateDateTime();
    _loadLocation();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) _updateDateTime();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCheckInStatus();
    });
  }

  void _onNotesChanged() {
    if (mounted) setState(() {});
  }

  void _updateDateTime() {
    final now = DateTime.now();
    if (!mounted) return;
    setState(() {
      _currentTime = DateFormat('hh:mm a').format(now);
      _currentDate = DateFormat('EEEE, d MMMM yyyy').format(now);
    });
  }

  Future<void> _loadCheckInStatus() async {
    final user = Provider.of<AuthProvider>(context, listen: false).user;
    if (user == null) {
      if (mounted) setState(() => _pageLoading = false);
      return;
    }

    final punchRes = await _service.getLastPunchStatus(user.systemUserId);
    final result = await _service.getLastCheckInStatus(user.systemUserId);
    if (!mounted) return;

    final punchedIn =
        punchRes['success'] == true && punchRes['isClockedIn'] == true;

    if (result['success'] == true && result['isCheckedIn'] == true) {
      final raw = result['raw'];
      if (raw is Map) {
        _checkInTimeLabel = (raw['time'] ?? '').toString();
        _checkInDateLabel = (raw['date'] ?? '').toString();
      }
      setState(() {
        _checkedIn = true;
        _isPunchedIn = punchedIn;
        _pageLoading = false;
      });
    } else {
      setState(() {
        _checkedIn = false;
        _isPunchedIn = punchedIn;
        _checkInTimeLabel = '';
        _checkInDateLabel = '';
        _pageLoading = false;
      });
    }
  }

  Future<void> _loadLocation() async {
    setState(() {
      _isLoadingLocation = true;
      _locationError = false;
    });
    try {
      final position = await LocationService.getCurrentLocation();
      if (!mounted) return;
      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
        _locationAddress =
            '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}';
        _isLoadingLocation = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _locationAddress = 'Unable to get location';
          _isLoadingLocation = false;
          _locationError = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _notesController.removeListener(_onNotesChanged);
    _clockTimer?.cancel();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _capturePhoto({required bool forCheckOut}) async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 70,
      );
      if (photo != null && mounted) {
        setState(() {
          if (forCheckOut) {
            _checkOutPhotoPath = photo.path;
          } else {
            _checkInPhotoPath = photo.path;
          }
        });
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
      _showMessage(message, isError: true);
    } catch (_) {
      if (!mounted) return;
      _showMessage(
        'Something went wrong while opening the camera.',
        isError: true,
      );
    }
  }

  Future<void> _handleCheckIn() async {
    if (_checkInPhotoPath == null) {
      _showMessage('Please capture a photo first.', isError: true);
      return;
    }
    if (_latitude == null || _longitude == null) {
      _showMessage(
        'Location is required. Please wait or refresh location.',
        isError: true,
      );
      return;
    }

    final user = Provider.of<AuthProvider>(context, listen: false).user;
    if (user == null) return;

    final punchRes = await _service.getLastPunchStatus(user.systemUserId);
    if (!mounted) return;
    if (punchRes['success'] == true && punchRes['isClockedIn'] != true) {
      setState(() => _isPunchedIn = false);
      _showMessage(
        'Please punch in (Attendance) before visit check-in.',
        isError: true,
      );
      return;
    }
    setState(() => _isPunchedIn = true);

    setState(() {
      _isCheckingIn = true;
    });

    final result = await _service.checkIn(
      systemUserId: user.systemUserId,
      latitude: _latitude!,
      longitude: _longitude!,
      photoPath: _checkInPhotoPath!,
    );

    if (!mounted) return;
    setState(() => _isCheckingIn = false);

    if (result['success'] == true) {
      final now = DateTime.now();
      final msg = result['message']?.toString() ?? 'Checked in successfully.';
      setState(() {
        _checkedIn = true;
        _checkInTimeLabel = DateFormat('hh:mm a').format(now);
        _checkInDateLabel = DateFormat('dd/MM/yyyy').format(now);
        _checkInPhotoPath = null;
        _checkOutPhotoPath = null;
      });
      _showMessage(msg, isError: false);
    } else {
      _showMessage(
        result['message']?.toString() ?? 'Check-in failed.',
        isError: true,
      );
    }
  }

  Future<void> _handleCheckOut() async {
    if (!_checkedIn) {
      _showMessage('Please complete Check In first.', isError: true);
      return;
    }
    if (_checkOutPhotoPath == null) {
      _showMessage('Please capture a new photo for Check Out.', isError: true);
      return;
    }
    if (_latitude == null || _longitude == null) {
      _showMessage(
        'Location is required. Please wait or refresh location.',
        isError: true,
      );
      return;
    }
    final notes = _notesController.text.trim();
    if (notes.isEmpty) {
      _showMessage('Notes are required for check-out.', isError: true);
      return;
    }

    setState(() {
      _isCheckingOut = true;
    });

    final user = Provider.of<AuthProvider>(context, listen: false).user;
    if (user == null) {
      setState(() => _isCheckingOut = false);
      return;
    }

    final result = await _service.checkOut(
      systemUserId: user.systemUserId,
      latitude: _latitude!,
      longitude: _longitude!,
      notes: notes,
      photoPath: _checkOutPhotoPath!,
    );

    if (!mounted) return;
    setState(() => _isCheckingOut = false);

    if (result['success'] == true) {
      _showMessage(
        result['message']?.toString() ?? 'Checked out successfully.',
        isError: false,
      );
      Future.delayed(const Duration(milliseconds: 400), () {
        if (!mounted) return;
        Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
      });
    } else {
      _showMessage(
        result['message']?.toString() ?? 'Check-out failed.',
        isError: true,
      );
    }
  }

  void _showMessage(String msg, {required bool isError}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        backgroundColor: isError ? Colors.redAccent : Colors.black87,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(
          _checkedIn ? 'Visit Check Out' : 'Visit Check In',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh status',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _pageLoading
                ? null
                : () async {
                    setState(() => _pageLoading = true);
                    await _loadCheckInStatus();
                  },
          ),
        ],
      ),
      body: SafeArea(
        child: _pageLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: _checkedIn
                    ? _buildCheckedInContent()
                    : _buildCheckInContent(),
              ),
      ),
    );
  }

  Widget _buildCheckInContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildDateTimeCard(),
        const SizedBox(height: 20),
        if (!_isPunchedIn) ...[
          _buildPunchInRequiredCard(),
          const SizedBox(height: 20),
        ],
        _buildLocationCard(),
        const SizedBox(height: 20),
        _buildCheckInPhotoCard(),
        const SizedBox(height: 28),
        _buildCheckInButton(),
      ],
    );
  }

  Widget _buildCheckedInContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildDateTimeCard(),
        const SizedBox(height: 20),
        _buildCheckedInStatusCard(),
        const SizedBox(height: 20),
        _buildLocationCard(),
        const SizedBox(height: 20),
        _buildCheckOutPhotoCard(),
        const SizedBox(height: 20),
        _buildCheckOutNotesCard(),
        const SizedBox(height: 28),
        _buildCheckOutButton(),
      ],
    );
  }

  Widget _buildDateTimeCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            _currentTime,
            style: GoogleFonts.outfit(
              fontSize: 42,
              fontWeight: FontWeight.bold,
              color: Colors.black,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _currentDate,
            style: GoogleFonts.outfit(
              fontSize: 15,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckedInStatusCard() {
    final timeStr = _checkInTimeLabel.isNotEmpty ? _checkInTimeLabel : '--:--';
    final dateStr = _checkInDateLabel.isNotEmpty ? _checkInDateLabel : '';

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.teal.shade600, Colors.teal.shade800],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.teal.withOpacity(0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'CHECKED IN',
              style: GoogleFonts.outfit(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 0.8,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Icon(
            Icons.login_rounded,
            size: 40,
            color: Colors.white.withOpacity(0.95),
          ),
          const SizedBox(height: 12),
          Text(
            'You\'re checked in at this visit',
            style: GoogleFonts.outfit(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            timeStr,
            style: GoogleFonts.outfit(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          if (dateStr.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              dateStr,
              style: GoogleFonts.outfit(
                fontSize: 14,
                color: Colors.white.withOpacity(0.9),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLocationCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.teal.withOpacity(0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.location_on_rounded,
              color: Colors.teal[700],
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your location',
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    color: Colors.grey[500],
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                if (_isLoadingLocation)
                  const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Text(
                    _locationAddress,
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: _locationError ? Colors.red[700] : Colors.black87,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (!_isLoadingLocation)
            TextButton.icon(
              onPressed: _loadLocation,
              icon: Icon(
                Icons.refresh_rounded,
                size: 18,
                color: Colors.grey[600],
              ),
              label: Text(
                'Refresh',
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCheckInPhotoCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.camera_alt_rounded, color: Colors.grey[700], size: 20),
              const SizedBox(width: 8),
              Text(
                'Check-in photo',
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: _isCheckingIn
                ? null
                : () => _capturePhoto(forCheckOut: false),
            child: Container(
              height: 200,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _checkInPhotoPath != null
                      ? Colors.teal
                      : Colors.grey[300]!,
                  width: _checkInPhotoPath != null ? 2 : 1,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: _checkInPhotoPath != null
                  ? Image.file(File(_checkInPhotoPath!), fit: BoxFit.cover)
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.add_a_photo_rounded,
                          size: 40,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Tap to capture',
                          style: GoogleFonts.outfit(
                            color: Colors.grey[600],
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckOutPhotoCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.camera_alt_rounded, color: Colors.grey[700], size: 20),
              const SizedBox(width: 8),
              Text(
                'Check-out photo',
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: _isCheckingOut
                ? null
                : () => _capturePhoto(forCheckOut: true),
            child: Container(
              height: 160,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _checkOutPhotoPath != null
                      ? Colors.orange
                      : Colors.grey[300]!,
                  width: _checkOutPhotoPath != null ? 2 : 1,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: _checkOutPhotoPath != null
                  ? Image.file(File(_checkOutPhotoPath!), fit: BoxFit.cover)
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.add_a_photo_rounded,
                          size: 36,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'New photo required (not the check-in photo)',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.outfit(
                            color: Colors.grey[600],
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckOutNotesCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
        border: Border.all(color: Colors.grey[300]!, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.edit_note_rounded,
                  color: Colors.red.shade700,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Check-out notes',
                      style: GoogleFonts.outfit(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Describe the visit or purpose before checking out.',
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        color: Colors.grey[700],
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _notesController,
            minLines: 4,
            maxLines: 6,
            style: GoogleFonts.outfit(
              fontSize: 16,
              color: Colors.black87,
              height: 1.4,
            ),
            decoration: InputDecoration(
              hintText: 'Type your notes here…',
              hintStyle: GoogleFonts.outfit(
                fontSize: 16,
                color: Colors.grey[500],
              ),
              filled: true,
              fillColor: const Color(0xFFF5F5F7),
              contentPadding: const EdgeInsets.all(16),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: Colors.grey[400]!, width: 1.5),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: Colors.red.shade400, width: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPunchInRequiredCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: Colors.orange.shade800),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'You must punch in on the Attendance screen before you can check in for a visit.',
              style: GoogleFonts.outfit(
                fontSize: 14,
                color: Colors.orange.shade900,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckInButton() {
    final canSubmit =
        _latitude != null && _longitude != null && !_isLoadingLocation;

    return SizedBox(
      height: 56,
      child: ElevatedButton.icon(
        onPressed: (canSubmit && !_isCheckingIn) ? _handleCheckIn : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        icon: _isCheckingIn
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.login_rounded, size: 22),
        label: Text(
          _isCheckingIn ? 'Checking in...' : 'Check In',
          style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildCheckOutButton() {
    final hasNotes = _notesController.text.trim().isNotEmpty;
    final readyToSubmit =
        _latitude != null &&
        _longitude != null &&
        !_isLoadingLocation &&
        _checkOutPhotoPath != null &&
        hasNotes;

    return SizedBox(
      height: 56,
      child: OutlinedButton.icon(
        // Always call _handleCheckOut so validation messages (SnackBars) show
        // when photo, notes, or location are missing.
        onPressed: !_isCheckingOut ? _handleCheckOut : null,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.red.shade700,
          side: BorderSide(
            color: readyToSubmit && !_isCheckingOut
                ? Colors.red.shade700
                : Colors.grey[300]!,
            width: 2,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        icon: _isCheckingOut
            ? SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.red.shade700,
                ),
              )
            : const Icon(Icons.logout_rounded, size: 22),
        label: Text(
          _isCheckingOut ? 'Checking out...' : 'Check Out',
          style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
