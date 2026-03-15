import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class TripService {
  static const String _baseUrl = 'https://salestracker.kureone.com';
  static const Duration _timeout = Duration(seconds: 30);

  /// Start Trip API
  /// Creates a new trip with start and end locations
  Future<Map<String, dynamic>> startTrip({
    required int systemUserId,
    required String name,
    required String fromLocation,
    required String toLocation,
    required String purpose,
    required double fromLocationLatitude,
    required double fromLocationLongitude,
    required double toLocationLatitude,
    required double toLocationLongitude,
  }) async {
    try {
      final url = Uri.parse(
        '$_baseUrl/StartTripApi.htm?'
        'system_user_id=$systemUserId&'
        'name=${Uri.encodeComponent(name)}&'
        'from_location=${Uri.encodeComponent(fromLocation)}&'
        'to_location=${Uri.encodeComponent(toLocation)}&'
        'purpose=${Uri.encodeComponent(purpose)}&'
        'from_location_latitude=$fromLocationLatitude&'
        'from_location_longitude=$fromLocationLongitude&'
        'to_location_latitude=$toLocationLatitude&'
        'to_location_longitude=$toLocationLongitude',
      );

      final response = await http
          .get(url)
          .timeout(
            _timeout,
            onTimeout: () {
              throw TimeoutException(
                'Connection is slow. Please check your internet connection.',
              );
            },
          );

      if (response.statusCode == 200) {
        final dynamic data = json.decode(response.body);

        if (data is Map<String, dynamic> &&
            data['data'] is List &&
            (data['data'] as List).isNotEmpty) {
          final result = (data['data'] as List)[0];

          if (result is Map<String, dynamic>) {
            final message = result['message']?.toString() ?? '';

            // Check for success
            if (message.toLowerCase().contains('success') ||
                message.toLowerCase().contains('created') ||
                message.toLowerCase().contains('started')) {
              return {
                'success': true,
                'message': message,
                'trip_id':
                    result['trip_id']?.toString() ??
                    result['trips_id']?.toString(),
                'data': result,
              };
            } else {
              return {
                'success': false,
                'message': message.isNotEmpty
                    ? message
                    : 'Failed to start trip',
              };
            }
          }
        }

        return {'success': false, 'message': 'Invalid response from server'};
      } else {
        return {
          'success': false,
          'message': 'Server error: ${response.statusCode}',
        };
      }
    } on SocketException {
      return {
        'success': false,
        'message': 'No internet connection. Please check your network.',
      };
    } on TimeoutException catch (e) {
      return {
        'success': false,
        'message': e.message ?? 'Connection timeout. Please try again.',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'An error occurred: ${e.toString()}',
      };
    }
  }

  /// Add Trip Location API
  /// Send current location during active trip (called every 5 seconds)
  Future<Map<String, dynamic>> addTripLocation({
    required int systemUserId,
    required String tripsId,
    required double latitude,
    required double longitude,
  }) async {
    try {
      final url = Uri.parse(
        '$_baseUrl/AddTripLocationApi.htm?'
        'system_user_id=$systemUserId&'
        'trips_id=$tripsId&'
        'latitude=$latitude&'
        'longitude=$longitude',
      );

      final response = await http
          .get(url)
          .timeout(
            const Duration(seconds: 10), // Shorter timeout for frequent calls
            onTimeout: () {
              throw TimeoutException('Location update timeout');
            },
          );

      if (response.statusCode == 200) {
        final dynamic data = json.decode(response.body);

        if (data is Map<String, dynamic>) {
          // Even if there's no explicit success message, 200 status means success
          return {'success': true, 'message': 'Location updated', 'data': data};
        }

        return {'success': true, 'message': 'Location updated'};
      } else {
        return {
          'success': false,
          'message': 'Server error: ${response.statusCode}',
        };
      }
    } on SocketException {
      return {'success': false, 'message': 'No internet connection'};
    } on TimeoutException {
      return {'success': false, 'message': 'Location update timeout'};
    } catch (e) {
      return {'success': false, 'message': 'Error: ${e.toString()}'};
    }
  }

  /// End Trip API
  /// End the active trip with total kilometers traveled
  Future<Map<String, dynamic>> endTrip({
    required int systemUserId,
    required String tripsId,
    required double kilometer,
    required String notes,
    List<Map<String, dynamic>>? expenseItems,
  }) async {
    try {
      String extraParams = "";
      if (expenseItems != null && expenseItems.isNotEmpty) {
        String jsonExpense = jsonEncode(expenseItems);
        String encodedExpense = Uri.encodeComponent(jsonExpense);
        extraParams = "&expense_items=$encodedExpense";
      }

      final url = Uri.parse(
        '$_baseUrl/EndTripApi.htm?'
        'system_user_id=$systemUserId&'
        'trips_id=$tripsId&'
        'kilometer=$kilometer&'
        'notes=${Uri.encodeComponent(notes)}'
        '$extraParams',
      );

      final response = await http
          .get(url)
          .timeout(
            _timeout,
            onTimeout: () {
              throw TimeoutException(
                'Connection is slow. Please check your internet connection.',
              );
            },
          );

      if (response.statusCode == 200) {
        final dynamic data = json.decode(response.body);

        if (data is Map<String, dynamic> &&
            data['data'] is List &&
            (data['data'] as List).isNotEmpty) {
          final result = (data['data'] as List)[0];

          if (result is Map<String, dynamic>) {
            final message = result['message']?.toString() ?? '';

            // Check for success
            if (message.toLowerCase().contains('success') ||
                message.toLowerCase().contains('ended') ||
                message.toLowerCase().contains('complete')) {
              return {'success': true, 'message': message, 'data': result};
            } else {
              return {
                'success': false,
                'message': message.isNotEmpty ? message : 'Failed to end trip',
              };
            }
          }
        }

        return {'success': false, 'message': 'Invalid response from server'};
      } else {
        return {
          'success': false,
          'message': 'Server error: ${response.statusCode}',
        };
      }
    } on SocketException {
      return {
        'success': false,
        'message': 'No internet connection. Please check your network.',
      };
    } on TimeoutException catch (e) {
      return {
        'success': false,
        'message': e.message ?? 'Connection timeout. Please try again.',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'An error occurred: ${e.toString()}',
      };
    }
  }

  /// Get Trips API
  /// Get all trips for a user
  Future<Map<String, dynamic>> getTrips({required int systemUserId}) async {
    try {
      final url = Uri.parse(
        '$_baseUrl/GetTripsApi.htm?system_user_id=$systemUserId',
      );

      final response = await http
          .get(url)
          .timeout(
            _timeout,
            onTimeout: () {
              throw TimeoutException(
                'Connection is slow. Please check your internet connection.',
              );
            },
          );

      if (response.statusCode == 200) {
        final dynamic data = json.decode(response.body);

        if (data is Map<String, dynamic> && data['data'] is List) {
          return {
            'success': true,
            'message': 'Trips fetched successfully',
            'trips': data['data'],
          };
        }

        return {'success': false, 'message': 'Invalid response from server'};
      } else {
        return {
          'success': false,
          'message': 'Server error: ${response.statusCode}',
        };
      }
    } on SocketException {
      return {
        'success': false,
        'message': 'No internet connection. Please check your network.',
      };
    } on TimeoutException catch (e) {
      return {
        'success': false,
        'message': e.message ?? 'Connection timeout. Please try again.',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'An error occurred: ${e.toString()}',
      };
    }
  }

  /// Get Trip Details API
  /// Get detailed information about a specific trip including all stops
  Future<Map<String, dynamic>> getTripDetails({
    required int systemUserId,
    required String tripsId,
  }) async {
    try {
      final url = Uri.parse(
        '$_baseUrl/GetTripDetailsApi.htm?'
        'system_user_id=$systemUserId&'
        'trips_id=$tripsId',
      );

      final response = await http
          .get(url)
          .timeout(
            _timeout,
            onTimeout: () {
              throw TimeoutException(
                'Connection is slow. Please check your internet connection.',
              );
            },
          );

      if (response.statusCode == 200) {
        final dynamic data = json.decode(response.body);

        if (data is Map<String, dynamic>) {
          return {
            'success': true,
            'message': 'Trip details fetched successfully',
            'trip_data':
                data['data'] is List && (data['data'] as List).isNotEmpty
                ? (data['data'] as List)[0]
                : null,
            'stops': data['stops'] ?? [],
          };
        }

        return {'success': false, 'message': 'Invalid response from server'};
      } else {
        return {
          'success': false,
          'message': 'Server error: ${response.statusCode}',
        };
      }
    } on SocketException {
      return {
        'success': false,
        'message': 'No internet connection. Please check your network.',
      };
    } on TimeoutException catch (e) {
      return {
        'success': false,
        'message': e.message ?? 'Connection timeout. Please try again.',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'An error occurred: ${e.toString()}',
      };
    }
  }

  /// Get cached trips from local storage
  Future<List<dynamic>?> getCachedTrips() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? tripsJson = prefs.getString('cached_trips');
      if (tripsJson != null) {
        return json.decode(tripsJson);
      }
    } catch (e) {
      print('Error reading cached trips: $e');
    }
    return null;
  }

  /// Save trips to local storage
  Future<void> cacheTrips(List<dynamic> trips) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cached_trips', json.encode(trips));
    } catch (e) {
      print('Error caching trips: $e');
    }
  }

  /// Schedule Trip APIs

  Future<Map<String, dynamic>> createPlan({
    required int systemUserId,
    required String name,
    required String description,
    required String date,
    required String approvalRequired,
  }) async {
    try {
      final url = Uri.parse(
        '$_baseUrl/CreatePlanApi.htm?'
        'system_user_id=$systemUserId&'
        'name=${Uri.encodeComponent(name)}&'
        'description=${Uri.encodeComponent(description)}&'
        'date=${Uri.encodeComponent(date)}&'
        'approvalRequired=${Uri.encodeComponent(approvalRequired)}',
      );

      final response = await http.get(url).timeout(_timeout);

      if (response.statusCode == 200) {
        final dynamic data = json.decode(response.body);
        if (data != null &&
            data['data'] != null &&
            (data['data'] as List).isNotEmpty) {
          return {
            'success': true,
            'plans_id': data['data'][0]['plans_id'],
            'message':
                data['data'][0]['message'] ?? 'Plan created successfully',
          };
        }
        return {'success': false, 'message': 'Invalid response from server'};
      }
      return {'success': false, 'message': 'API error: ${response.statusCode}'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
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
    try {
      final url = Uri.parse(
        '$_baseUrl/ScheduleTripApi.htm?'
        'system_user_id=$systemUserId&'
        'plans_id=$plansId&'
        'from_location=${Uri.encodeComponent(fromLocation)}&'
        'to_location=${Uri.encodeComponent(toLocation)}&'
        'remarks=${Uri.encodeComponent(remarks)}&'
        'from_location_latitude=$fromLat&'
        'from_location_longitude=$fromLng&'
        'to_location_latitude=$toLat&'
        'to_location_longitude=$toLng',
      );

      final response = await http.get(url).timeout(_timeout);

      if (response.statusCode == 200) {
        final dynamic data = json.decode(response.body);
        if (data != null &&
            data['data'] != null &&
            (data['data'] as List).isNotEmpty) {
          return {
            'success': true,
            'trips_id': data['data'][0]['trips_id'],
            'message':
                data['data'][0]['message'] ?? 'Trip scheduled successfully',
          };
        }
        return {'success': false, 'message': 'Invalid response from server'};
      }
      return {'success': false, 'message': 'API error: ${response.statusCode}'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> submitPlanForApproval({
    required int systemUserId,
    required int plansId,
  }) async {
    try {
      final url = Uri.parse(
        '$_baseUrl/SubmitPlanForApprovalApi.htm?'
        'system_user_id=$systemUserId&'
        'plans_id=$plansId',
      );

      final response = await http.get(url).timeout(_timeout);

      if (response.statusCode == 200) {
        final dynamic data = json.decode(response.body);
        return {
          'success': true,
          'message': data['message'] ?? 'Plan submitted successfully',
        };
      }
      return {'success': false, 'message': 'API error: ${response.statusCode}'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> getPlans(int systemUserId) async {
    try {
      final url = Uri.parse(
        '$_baseUrl/GetPlansApi.htm?system_user_id=$systemUserId',
      );
      final response = await http.get(url).timeout(_timeout);

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        if (data['data'] != null) {
          return {'success': true, 'data': data['data']};
        }
        return {'success': false, 'message': 'No data found'};
      }
      return {'success': false, 'message': 'Error: ${response.statusCode}'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> getTripsByPlan(
    int systemUserId,
    int plansId,
  ) async {
    try {
      final url = Uri.parse(
        '$_baseUrl/GetTripsByPlansApi.htm?system_user_id=$systemUserId&plans_id=$plansId',
      );
      final response = await http.get(url).timeout(_timeout);

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        if (data['data'] != null) {
          return {'success': true, 'data': data['data']};
        }
        return {'success': false, 'message': 'No data found'};
      }
      return {'success': false, 'message': 'Error: ${response.statusCode}'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> startScheduledTrip(
    int systemUserId,
    int tripsId,
  ) async {
    try {
      final url = Uri.parse(
        '$_baseUrl/StartScheduledTripApi.htm?system_user_id=$systemUserId&trips_id=$tripsId',
      );
      final response = await http.get(url).timeout(_timeout);

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        if (data['data'] != null && (data['data'] as List).isNotEmpty) {
          return {
            'success': true,
            'message': data['message'] ?? 'Trip started',
            'trips_id':
                data['data'][0]['trips_id'], // Return trips_id explicitly for local state tracking
          };
        }
        // Handle direct success messages if data list is empty but status is 200
        return {
          'success': true,
          'message': data['message'] ?? 'Trip started successfully',
        };
      }
      return {'success': false, 'message': 'Error: ${response.statusCode}'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  /// Clear cached trips
  Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('cached_trips');
    } catch (e) {
      print('Error clearing cache: $e');
    }
  }

  /// Get Expense Types API
  Future<Map<String, dynamic>> getExpenseTypes(int systemUserId) async {
    try {
      final url = Uri.parse(
        '$_baseUrl/GetExpenseTypesApi.htm?system_user_id=$systemUserId',
      );

      final response = await http.get(url).timeout(_timeout);

      if (response.statusCode == 200) {
        final dynamic data = json.decode(response.body);
        if (data is Map<String, dynamic> && data['data'] != null) {
          return {'success': true, 'data': data['data']};
        }
        return {'success': false, 'message': 'Invalid response from server'};
      } else {
        return {
          'success': false,
          'message': 'API error: ${response.statusCode}',
        };
      }
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }
}
