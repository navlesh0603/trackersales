import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionUtil {
  static bool _isShowing = false;

  /// Returns true if all mandatory permissions are granted.
  /// Proactively requests permissions if they are not granted.
  static Future<bool> checkMandatoryPermissions(BuildContext context) async {
    // 1. Notification Permission (Android 13+)
    if (!kIsWeb) {
      var notifStatus = await Permission.notification.status;
      if (notifStatus.isDenied) {
        debugPrint("Requesting notification permission...");
        notifStatus = await Permission.notification.request();
      }
    }

    // 2. Check Location Service (GPS)
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (context.mounted) {
        _showServiceDialog(
          context,
          "GPS Disabled",
          "Please enable GPS/Location services to use this app for tracking.",
          Geolocator.openLocationSettings,
        );
      }
      return false;
    }

    // 3. Location Permission (Foreground)
    var locStatus = await Permission.location.status;

    // On Android 12+, it might be 'limited' (Approximate) if the user didn't give Precise
    if (locStatus.isDenied) {
      debugPrint("Requesting location permission...");
      locStatus = await Permission.location.request();
    }

    if (locStatus.isPermanentlyDenied) {
      if (context.mounted) {
        _showServiceDialog(
          context,
          "Location Permission",
          "Location access is mandatory for trip tracking. Please allow 'While using the app' or 'Always' in settings.",
          openAppSettings,
        );
      }
      return false;
    }

    if (!locStatus.isGranted && !locStatus.isLimited) return false;

    // 4. Background Location (Android 10+)
    if (kIsWeb) {
      // Background location isn't a concept on web, so if foreground is granted, we're good
      return true;
    }

    var alwaysStatus = await Permission.locationAlways.status;
    if (alwaysStatus.isGranted) return true;

    if (context.mounted) {
      // For Android 11+, it's mandatory to explain why background location is needed
      // before taking them to the settings page.
      final proceed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Row(
            children: [
              Icon(Icons.security_rounded, color: Colors.blue),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  "Background Tracking",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: const Text(
            "This app collects location data to track your sales trips even when the app is closed or not in use. "
            "\n\nTo enable this, please select 'Allow all the time' in the next screen.",
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  "Give Access",
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      );

      if (proceed == true) {
        debugPrint("Requesting Background location permission...");
        alwaysStatus = await Permission.locationAlways.request();
      }
    }

    return alwaysStatus.isGranted;
  }

  static void _showServiceDialog(
    BuildContext context,
    String title,
    String message,
    VoidCallback onOpenSettings,
  ) {
    if (_isShowing) return;
    _isShowing = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Text(message),
          actions: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  _isShowing = false;
                  Navigator.of(context).pop();
                  onOpenSettings();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  "Open Settings",
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    ).then((_) => _isShowing = false);
  }
}
