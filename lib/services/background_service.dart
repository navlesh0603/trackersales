import 'dart:async';
import 'dart:ui';
import 'dart:convert';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

Future<void> initializeService() async {
  try {
    final service = FlutterBackgroundService();

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'trip_tracking_channel',
      'Active Trip Tracking',
      description: 'This channel is used for live trip tracking updates.',
      importance:
          Importance.low, // Changed from max to low to avoid noise every 5s
    );

    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: 'trip_tracking_channel',
        initialNotificationTitle: 'Trip Tracking Started',
        initialNotificationContent: 'Initializing live route marking...',
        foregroundServiceNotificationId: 888,
        foregroundServiceTypes: [AndroidForegroundType.location],
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );
  } catch (e) {
    print('Error initializing background service: $e');
  }
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  return true;
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  double totalDistance = 0.0;
  Position? lastPosition;
  StreamSubscription<Position>? positionSubscription;
  List<Map<String, double>> pathPoints = [];

  // Persistence: Fetch start time, current distance and path from shared prefs
  final prefs = await SharedPreferences.getInstance();
  final storedStart = prefs.getString('active_trip_start_time');
  final storedDist = prefs.getDouble('active_trip_distance') ?? 0.0;
  final storedPath = prefs.getString('active_trip_path');
  final storedTripId = prefs.getString('active_trip_id');
  final storedUserId = prefs.getInt('system_user_id');

  totalDistance = storedDist;
  if (storedPath != null) {
    try {
      final List<dynamic> decoded = json.decode(storedPath);
      pathPoints = decoded.map((e) => Map<String, double>.from(e)).toList();
    } catch (e) {
      print('Error decoding stored path: $e');
    }
  }

  final startTime = storedStart != null
      ? DateTime.parse(storedStart)
      : DateTime.now();

  print(
    'Background service starting: Trip $storedTripId, User $storedUserId, Distance: $totalDistance, Points: ${pathPoints.length}',
  );

  // Helper function to send location to server
  Future<void> syncLocation(double lat, double lng) async {
    if (storedTripId == null || storedUserId == null) return;
    try {
      final url = Uri.parse(
        'https://salestracker.kureone.com/AddTripLocationApi.htm?'
        'system_user_id=$storedUserId&'
        'trips_id=$storedTripId&'
        'latitude=$lat&'
        'longitude=$lng',
      );
      await http.get(url).timeout(const Duration(seconds: 10));
    } catch (e) {
      print("BG Sync Error: $e");
    }
  }

  if (service is AndroidServiceInstance) {
    service.setAsForegroundService();

    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });

    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  service.on('stopService').listen((event) async {
    await positionSubscription?.cancel();
    // Clear trip data on stop
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('active_trip_distance');
    await prefs.remove('active_trip_path');
    await prefs.remove('active_trip_start_time');
    await prefs.remove('active_trip_id');
    service.stopSelf();
  });

  // Use getPositionStream for continuous tracking
  positionSubscription =
      Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best, // High accuracy for precise tracking
          distanceFilter: 0, // Emission on every update
        ),
      ).listen((position) async {
        // Best Algorithm for distance: Filter out GPS jitter
        // If accuracy is poor, skip this point for distance calculation
        if (position.accuracy > 40) {
          print("BG: skipping point due to low accuracy: ${position.accuracy}");
          return;
        }

        double distanceMeters = 0;
        if (lastPosition != null) {
          distanceMeters = Geolocator.distanceBetween(
            lastPosition!.latitude,
            lastPosition!.longitude,
            position.latitude,
            position.longitude,
          );

          // Filtering: If distance is too small (e.g. < 5m), it might be GPS noise
          // Or if speed is basically 0, don't add distance.
          if (distanceMeters < 5 && position.speed < 0.5) {
            distanceMeters = 0;
          }
        }

        lastPosition = position;

        final currentPoint = {
          "lat": position.latitude,
          "lng": position.longitude,
        };

        pathPoints.add(currentPoint);

        if (distanceMeters > 0) {
          // distance is in meters, convert to km
          totalDistance += (distanceMeters / 1000);
        }

        // Persist data for recovery
        final prefs = await SharedPreferences.getInstance();
        await prefs.setDouble('active_trip_distance', totalDistance);
        await prefs.setString('active_trip_path', json.encode(pathPoints));

        service.invoke('update', {
          "lat": position.latitude,
          "lng": position.longitude,
          "distance": totalDistance,
          "path": pathPoints,
        });
      });

  // Strict 5-second Sync Timer as requested
  Timer.periodic(const Duration(seconds: 5), (timer) async {
    if (lastPosition != null) {
      print("BG Sync: Every 5 seconds update...");
      syncLocation(lastPosition!.latitude, lastPosition!.longitude);
    } else {
      // If we haven't gotten a stream update, try to force-fetch
      try {
        Position pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
        lastPosition = pos;
        syncLocation(pos.latitude, pos.longitude);
      } catch (e) {
        print("BG force fetch failed: $e");
      }
    }
  });

  // Regular notification update timer (every 1s) to keep time current
  Timer.periodic(const Duration(seconds: 1), (timer) async {
    final duration = DateTime.now().difference(startTime);
    String timeStr = _formatDuration(duration);

    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: "Trip Tracking Active 🚀",
        content:
            "Distance: ${totalDistance.toStringAsFixed(2)} km | Time: $timeStr",
      );
    }
  });
}

String _formatDuration(Duration duration) {
  String twoDigits(int n) => n.toString().padLeft(2, "0");
  String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
  String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
  return "${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
}
