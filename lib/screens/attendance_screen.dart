import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trackersales/providers/auth_provider.dart';
import 'package:trackersales/services/attendance_service.dart';
import 'package:trackersales/services/location_service.dart';
import 'package:intl/intl.dart';
import 'dart:io';

const String _keyClockedIn = 'attendance_clocked_in';
const String _keyPunchInTime = 'attendance_punch_in_time';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  final AttendanceService _attendanceService = AttendanceService();

  String _currentTime = '';
  String _currentDate = '';
  String _locationAddress = '';
  double? _latitude;
  double? _longitude;
  bool _isLoadingLocation = true;
  bool _isPunchingIn = false;
  bool _isPunchingOut = false;
  String? _photoPath;
  bool _locationError = false;

  bool _isClockedIn = false;
  DateTime? _punchInTime;
  bool _loadingState = true;

  @override
  void initState() {
    super.initState();
    _updateDateTime();
    _loadLocation();
    _loadClockedInState();
    Future.delayed(Duration.zero, () {
      if (!mounted) return;
      _startTimeTimer();
    });
  }

  Future<void> _loadClockedInState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final clockedIn = prefs.getBool(_keyClockedIn) ?? false;
      final punchInTimeStr = prefs.getString(_keyPunchInTime);
      if (!mounted) return;
      setState(() {
        _isClockedIn = clockedIn;
        _punchInTime = punchInTimeStr != null
            ? DateTime.tryParse(punchInTimeStr)
            : null;
        _loadingState = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _isClockedIn = false;
          _punchInTime = null;
          _loadingState = false;
        });
      }
    }
  }

  Future<void> _saveClockedIn(DateTime punchInTime) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyClockedIn, true);
    await prefs.setString(_keyPunchInTime, punchInTime.toIso8601String());
  }

  Future<void> _clearClockedIn() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyClockedIn);
    await prefs.remove(_keyPunchInTime);
  }

  void _startTimeTimer() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      _updateDateTime();
      return true;
    });
  }

  void _updateDateTime() {
    final now = DateTime.now();
    setState(() {
      _currentTime = DateFormat('hh:mm a').format(now);
      _currentDate = DateFormat('EEEE, d MMMM yyyy').format(now);
    });
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
    } catch (e) {
      if (mounted) {
        setState(() {
          _locationAddress = 'Unable to get location';
          _isLoadingLocation = false;
          _locationError = true;
        });
      }
    }
  }

  Future<void> _capturePhoto() async {
    try {
      final picker = ImagePicker();
      final XFile? photo = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 70,
        maxWidth: 1024,
      );
      if (photo == null || !mounted) return;
      setState(() {
        _photoPath = photo.path;
      });
    } on PlatformException catch (e) {
      if (!mounted) return;
      String message;
      if (e.code == 'camera_access_denied' ||
          e.code == 'camera_access_denied_without_prompt') {
        message =
            'Camera permission was denied. You can enable it from app settings if you want to capture photos.';
      } else {
        message = 'Unable to open camera. Please try again.';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Something went wrong while opening the camera.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _punchIn() async {
    final user = Provider.of<AuthProvider>(context, listen: false).user;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please log in.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (_photoPath == null || _photoPath!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please take a photo before checking in.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    if (_latitude == null || _longitude == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Location is required. Please enable location and try again.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isPunchingIn = true);

    final result = await _attendanceService.punchIn(
      systemUserId: user.systemUserId,
      latitude: _latitude!,
      longitude: _longitude!,
      photoPath: _photoPath!,
    );

    if (!mounted) return;
    setState(() => _isPunchingIn = false);

    if (result['success'] == true) {
      final now = DateTime.now();
      await _saveClockedIn(now);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result['message']?.toString() ?? 'Punch-in successful!',
          ),
          backgroundColor: Colors.green,
        ),
      );
      setState(() {
        _photoPath = null;
        _isClockedIn = true;
        _punchInTime = now;
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message']?.toString() ?? 'Punch-in failed.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _punchOut() async {
    final user = Provider.of<AuthProvider>(context, listen: false).user;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please log in.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (_latitude == null || _longitude == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Location is required for punch-out. Please enable location and try again.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    if (_photoPath == null || _photoPath!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Photo is required for punch-out. Please capture one.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isPunchingOut = true);

    final result = await _attendanceService.punchOut(
      systemUserId: user.systemUserId,
      latitude: _latitude!,
      longitude: _longitude!,
      photoPath: _photoPath!,
    );

    if (!mounted) return;
    setState(() => _isPunchingOut = false);

    if (result['success'] == true) {
      await _clearClockedIn();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result['message']?.toString() ?? 'Punch-out successful!',
          ),
          backgroundColor: Colors.green,
        ),
      );
      setState(() {
        _isClockedIn = false;
        _punchInTime = null;
        _photoPath = null;
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message']?.toString() ?? 'Punch-out failed.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String _formatDuration(DateTime from) {
    final now = DateTime.now();
    final diff = now.difference(from);
    final hours = diff.inHours;
    final minutes = diff.inMinutes % 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(
          'Attendance',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18),
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
      body: SafeArea(
        child: _loadingState
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: _isClockedIn
                    ? _buildClockedInContent()
                    : _buildPunchInContent(),
              ),
      ),
    );
  }

  Widget _buildClockedInContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildDateTimeCard(),
        const SizedBox(height: 20),
        _buildClockedInStatusCard(),
        const SizedBox(height: 20),
        _buildLocationCard(),
        const SizedBox(height: 20),
        _buildPunchOutPhotoCard(),
        const SizedBox(height: 28),
        _buildPunchOutButton(),
      ],
    );
  }

  Widget _buildPunchInContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildDateTimeCard(),
        const SizedBox(height: 20),
        _buildLocationCard(),
        const SizedBox(height: 20),
        _buildPhotoCard(),
        const SizedBox(height: 28),
        _buildCheckInButton(),
      ],
    );
  }

  Widget _buildClockedInStatusCard() {
    final punchInStr = _punchInTime != null
        ? DateFormat('hh:mm a').format(_punchInTime!)
        : '--:--';
    final durationStr = _punchInTime != null
        ? _formatDuration(_punchInTime!)
        : '0m';

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.green.shade600, Colors.green.shade700],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.green.withOpacity(0.25),
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
              'CLOCKED IN',
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
            'You\'re Punched in',
            style: GoogleFonts.outfit(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Since $punchInStr',
            style: GoogleFonts.outfit(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Duration: $durationStr',
            style: GoogleFonts.outfit(
              fontSize: 14,
              color: Colors.white.withOpacity(0.9),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPunchOutPhotoCard() {
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
                'Punch-out photo',
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
            onTap: _capturePhoto,
            child: Container(
              height: 160,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _photoPath != null ? Colors.orange : Colors.grey[300]!,
                  width: _photoPath != null ? 2 : 1,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: _photoPath != null
                  ? Image.file(File(_photoPath!), fit: BoxFit.cover)
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
                          'Tap to add photo',
                          style: GoogleFonts.outfit(
                            fontSize: 13,
                            color: Colors.grey[500],
                            fontWeight: FontWeight.w500,
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

  Widget _buildPunchOutButton() {
    final canPunchOut =
        _latitude != null &&
        _longitude != null &&
        !_isLoadingLocation &&
        _photoPath != null &&
        _photoPath!.isNotEmpty;

    return SizedBox(
      height: 56,
      child: OutlinedButton.icon(
        onPressed: (canPunchOut && !_isPunchingOut) ? _punchOut : null,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.red.shade700,
          side: BorderSide(
            color: canPunchOut && !_isPunchingOut
                ? Colors.red.shade700
                : Colors.grey[300]!,
            width: 2,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          disabledForegroundColor: Colors.grey[500],
        ),
        icon: _isPunchingOut
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.red,
                ),
              )
            : const Icon(Icons.logout_rounded, size: 22),
        label: Text(
          _isPunchingOut ? 'Punching out...' : 'Punch Out',
          style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.bold),
        ),
      ),
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
              color: Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.location_on_rounded,
              color: Colors.green[700],
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
                  SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.grey[400],
                    ),
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
              onPressed: _locationError ? _loadLocation : null,
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

  Widget _buildPhotoCard() {
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
                'Punch-in photo',
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
            onTap: _capturePhoto,
            child: Container(
              height: 200,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _photoPath != null ? Colors.green : Colors.grey[300]!,
                  width: _photoPath != null ? 2 : 1,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: _photoPath != null
                  ? Image.file(File(_photoPath!), fit: BoxFit.cover)
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.add_a_photo_rounded,
                          size: 48,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Tap to take photo',
                          style: GoogleFonts.outfit(
                            fontSize: 14,
                            color: Colors.grey[500],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          'Required for punch-in',
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            color: Colors.grey[400],
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

  Widget _buildCheckInButton() {
    final canSubmit =
        _photoPath != null &&
        _latitude != null &&
        _longitude != null &&
        !_isLoadingLocation;

    return SizedBox(
      height: 56,
      child: ElevatedButton.icon(
        onPressed: (canSubmit && !_isPunchingIn) ? _punchIn : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.black,
          disabledBackgroundColor: Colors.grey[300],
          foregroundColor: Colors.white,
          disabledForegroundColor: Colors.grey[500],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
        ),
        icon: _isPunchingIn
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
          _isPunchingIn ? 'Punching in...' : 'Punch In',
          style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
