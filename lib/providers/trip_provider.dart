import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:trackersales/models/trip.dart';
import 'package:trackersales/services/trip_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:io';
import 'package:trackersales/screens/trip_detail_screen.dart';
import 'package:trackersales/theme/app_theme.dart';

class TripProvider extends ChangeNotifier {
  final TripService _tripService = TripService();
  final List<Trip> _trips = [];
  Trip? _activeTrip;
  bool _isLoading = false;
  Timer? _locationTimer;
  int _systemUserId = 0;

  List<Trip> get trips => _trips;
  Trip? get activeTrip => _activeTrip;
  bool get isLoading => _isLoading;

  /// Start a new trip by calling the API
  Future<Map<String, dynamic>> startTrip({
    required int systemUserId,
    required Trip trip,
  }) async {
    _isLoading = true;
    notifyListeners();

    // The trip object already has the live start location from CreateTripScreen
    final result = await _tripService.startTrip(
      systemUserId: systemUserId,
      name: trip.title,
      fromLocation: trip.startAddress,
      toLocation: trip.endAddress,
      purpose: trip.description,
      fromLocationLatitude: trip.startLat,
      fromLocationLongitude: trip.startLng,
      toLocationLatitude: trip.endLat,
      toLocationLongitude: trip.endLng,
    );

    if (result['success']) {
      // Set the server trip ID
      trip.tripId = result['trip_id'];
      trip.isActive = true;
      trip.startTime = DateTime.now();

      _activeTrip = trip;
      _systemUserId = systemUserId;

      // Ensure the path starts with the live location
      if (trip.path.isEmpty) {
        trip.path = [LatLng(trip.startLat, trip.startLng)];
      }

      _trips.insert(0, trip);

      // Persistence
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'active_trip_start_time',
        trip.startTime.toIso8601String(),
      );
      await prefs.setString('active_trip_id', trip.tripId!);
      await prefs.setInt('system_user_id', systemUserId);
      await prefs.setDouble('active_trip_distance', 0.0);

      // Start location tracking timer (Every 5 seconds as requested)
      _startLocationTracking();

      // Initial location sync
      _sendLocationUpdate(trip.startLat, trip.startLng);
    }

    _isLoading = false;
    notifyListeners();
    return result;
  }

  /// Start sending location updates exactly every 5 seconds
  void _startLocationTracking() {
    _locationTimer?.cancel();
    _locationTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (_activeTrip != null) {
        try {
          // Get fresh position for the 5-sec update
          Position position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
          );
          _sendLocationUpdate(position.latitude, position.longitude);

          // Also update local path for UI
          final newLatLng = LatLng(position.latitude, position.longitude);
          updateCurrentPath(newLatLng);
        } catch (e) {
          debugPrint("Timer-based location fetch failed: $e");
        }
      }
    });
  }

  /// Send location update to server
  Future<void> _sendLocationUpdate(double latitude, double longitude) async {
    if (_activeTrip == null || _activeTrip!.tripId == null) return;

    debugPrint("Syncing location to server: $latitude, $longitude");
    await _tripService.addTripLocation(
      systemUserId: _systemUserId,
      tripsId: _activeTrip!.tripId!,
      latitude: latitude,
      longitude: longitude,
    );
  }

  /// End the active trip
  Future<Map<String, dynamic>> endTrip(
    double totalDistance,
    List<LatLng> finalPath,
    String notes,
    {List<Map<String, dynamic>>? expenseItems}
  ) async {
    if (_activeTrip == null) {
      return {'success': false, 'message': 'No active trip'};
    }

    _isLoading = true;
    notifyListeners();

    // Stop location tracking timer
    _locationTimer?.cancel();
    _locationTimer = null;

    // Send final live location before ending
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        timeLimit: const Duration(seconds: 5),
      );
      debugPrint(
        "Sending final live location before end: ${position.latitude}, ${position.longitude}",
      );
      await _sendLocationUpdate(position.latitude, position.longitude);
    } catch (e) {
      debugPrint("Could not get final live location: $e");
      // Fallback to last known path point if GPS fails at the end
      if (finalPath.isNotEmpty) {
        await _sendLocationUpdate(
          finalPath.last.latitude,
          finalPath.last.longitude,
        );
      }
    }

    final result = await _tripService.endTrip(
      systemUserId: _systemUserId,
      tripsId: _activeTrip!.tripId!,
      kilometer: totalDistance,
      notes: notes,
      expenseItems: expenseItems,
    );

    if (result['success']) {
      _activeTrip!.endTime = DateTime.now();
      _activeTrip!.distanceKm = totalDistance;
      _activeTrip!.path = finalPath;
      _activeTrip!.notes = notes;
      _activeTrip!.isActive = false;
      _activeTrip = null;

      // Clear persistence
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('active_trip_start_time');
      await prefs.remove('active_trip_id');
      await prefs.remove('system_user_id');
      await prefs.remove('active_trip_distance');
      await prefs.remove('active_trip_path');

      // Refresh the trips list from server to get the final status
      await fetchTrips(_systemUserId);
    }

    _isLoading = false;
    notifyListeners();
    return result;
  }

  /// Load cached trips from local storage
  Future<void> loadCachedTrips() async {
    final cachedData = await _tripService.getCachedTrips();
    if (cachedData != null) {
      _trips.clear();
      _trips.addAll(
        cachedData.map((data) => Trip.fromJson(data)).toList().reversed,
      );
      _restoreActiveTrip();
      notifyListeners();
    }
  }

  Future<void> _restoreActiveTrip() async {
    try {
      // Find the first trip that is marked as active
      final activeIndex = _trips.indexWhere((trip) => trip.isActive);

      if (activeIndex != -1) {
        _activeTrip = _trips[activeIndex];

        // Recovery of precise start time from SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        final storedStartTime = prefs.getString('active_trip_start_time');
        if (storedStartTime != null) {
          _activeTrip!.startTime = DateTime.parse(storedStartTime);
        }

        final storedDist = prefs.getDouble('active_trip_distance') ?? 0.0;
        _activeTrip!.distanceKm = storedDist;

        // Ensure background service is running if we have an active trip
        if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
          final service = FlutterBackgroundService();
          bool isRunning = await service.isRunning();
          if (!isRunning) {
            await service.startService();
          }
        }

        _startLocationTracking();
      } else {
        _activeTrip = null;
        _locationTimer?.cancel();
        _locationTimer = null;
      }
    } catch (e) {
      debugPrint("Error restoring active trip: $e");
      _activeTrip = null;
    }
  }

  /// Fetch Expense Types
  Future<Map<String, dynamic>> fetchExpenseTypes(int systemUserId) async {
    return await _tripService.getExpenseTypes(systemUserId);
  }

  /// Schedule Trip APIs
  Future<Map<String, dynamic>> createPlan({
    required int systemUserId,
    required String name,
    required String description,
    required String date,
    required String approvalRequired,
  }) async {
    return await _tripService.createPlan(
        systemUserId: systemUserId,
        name: name,
        description: description,
        date: date,
        approvalRequired: approvalRequired);
  }

  Future<Map<String, dynamic>> scheduleTrip({
    required int systemUserId,
    required int plansId,
    required String fromLocation,
    required String toLocation,
    required String remarks,
    required double fromLat,
    required double fromLng,
    required double toLat,
    required double toLng,
  }) async {
    return await _tripService.scheduleTrip(
        systemUserId: systemUserId,
        plansId: plansId,
        fromLocation: fromLocation,
        toLocation: toLocation,
        remarks: remarks,
        fromLat: fromLat,
        fromLng: fromLng,
        toLat: toLat,
        toLng: toLng);
  }

  Future<Map<String, dynamic>> submitPlanForApproval({
    required int systemUserId,
    required int plansId,
  }) async {
    return await _tripService.submitPlanForApproval(systemUserId: systemUserId, plansId: plansId);
  }

  Future<Map<String, dynamic>> getPlans(int systemUserId) async {
    return await _tripService.getPlans(systemUserId);
  }

  Future<Map<String, dynamic>> getTripsByPlan(int systemUserId, int plansId) async {
    return await _tripService.getTripsByPlan(systemUserId, plansId);
  }

  Future<Map<String, dynamic>> startScheduledTrip({
    required int systemUserId,
    required int tripsId,
    required String tripName,
    required String fromLocation,
    required String toLocation,
    required double lat,
    required double lng,
  }) async {
    if (_activeTrip != null) {
      return {
        'success': false,
        'message': "You already have a trip on. Finish your current trip then start this."
      };
    }
    _isLoading = true;
    notifyListeners();

    final result = await _tripService.startScheduledTrip(systemUserId, tripsId);

    if (result['success']) {
      // Initialize local trip object for tracking
      Trip trip = Trip(
        id: tripsId.toString(),
        tripId: tripsId.toString(),
        title: tripName,
        description: "Scheduled Trip",
        notes: "",
        startAddress: fromLocation,
        endAddress: toLocation,
        startLat: lat,
        startLng: lng,
        endLat: 0.0,
        endLng: 0.0,
        startTime: DateTime.now(),
        isActive: true,
      );

      _activeTrip = trip;
      _systemUserId = systemUserId;

      if (trip.path.isEmpty) {
        trip.path = [LatLng(lat, lng)];
      }

      // Persistence
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('active_trip_start_time', trip.startTime.toIso8601String());
      await prefs.setString('active_trip_id', tripsId.toString());
      await prefs.setInt('system_user_id', systemUserId);
      await prefs.setDouble('active_trip_distance', 0.0);

      _startLocationTracking();
      _sendLocationUpdate(lat, lng);
    }

    _isLoading = false;
    notifyListeners();
    return result;
  }

  /// Fetch all trips for the user
  Future<Map<String, dynamic>> fetchTrips(int systemUserId) async {
    _systemUserId = systemUserId;

    // Load cache first for immediate UI update
    if (_trips.isEmpty) {
      await loadCachedTrips();
    }

    _isLoading = true;
    notifyListeners();

    final result = await _tripService.getTrips(systemUserId: systemUserId);

    if (result['success']) {
      final List<dynamic> tripsData = result['trips'] ?? [];

      // Update cache
      await _tripService.cacheTrips(tripsData);

      _trips.clear();
      _trips.addAll(
        tripsData.map((data) => Trip.fromJson(data)).toList().reversed,
      );

      _restoreActiveTrip();
    }

    _isLoading = false;
    notifyListeners();
    return result;
  }

  /// Fetch trip details including all stops
  Future<Map<String, dynamic>> fetchTripDetails({
    required int systemUserId,
    required String tripsId,
  }) async {
    _isLoading = true;
    notifyListeners();

    final result = await _tripService.getTripDetails(
      systemUserId: systemUserId,
      tripsId: tripsId,
    );

    _isLoading = false;
    notifyListeners();
    return result;
  }

  void updateCurrentPath(LatLng position) {
    if (_activeTrip != null) {
      _activeTrip!.path = [..._activeTrip!.path, position];
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    super.dispose();
  }
}
