import 'package:google_maps_flutter/google_maps_flutter.dart';

class Trip {
  final String id; // Local ID
  String? tripId; // Server-side trip ID from API
  final String title;
  final String description;
  String notes;
  final String startAddress;
  String endAddress;
  final double startLat;
  final double startLng;
  double endLat;
  double endLng;
  DateTime startTime;
  DateTime? endTime;
  double distanceKm;
  List<LatLng> path;
  bool isActive;
  String status;

  Trip({
    required this.id,
    this.tripId,
    required this.title,
    required this.description,
    required this.notes,
    required this.startAddress,
    required this.endAddress,
    required this.startLat,
    required this.startLng,
    required this.endLat,
    required this.endLng,
    required this.startTime,
    this.endTime,
    this.distanceKm = 0.0,
    this.path = const [],
    this.isActive = false,
    this.status = '',
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'trip_id': tripId,
    'title': title,
    'description': description,
    'notes': notes,
    'startAddress': startAddress,
    'endAddress': endAddress,
    'startLat': startLat,
    'startLng': startLng,
    'endLat': endLat,
    'endLng': endLng,
    'startTime': startTime.toIso8601String(),
    'endTime': endTime?.toIso8601String(),
    'distanceKm': distanceKm,
    'isActive': isActive,
    'status': status,
  };

  factory Trip.fromJson(Map<dynamic, dynamic> json) {
    // Parse coordinates safely (they might be strings or numbers)
    double parseDouble(dynamic value) {
      if (value == null) return 0.0;
      if (value is num) return value.toDouble();
      return double.tryParse(value.toString()) ?? 0.0;
    }

    // Parse trips_id safely
    String? parseTripId(dynamic value) {
      if (value == null) return null;
      return value.toString();
    }

    // Parse date (DD/MM/YYYY)
    DateTime parseDate(dynamic dateVal) {
      if (dateVal == null) return DateTime.now();
      String dateStr = dateVal.toString();
      if (dateStr.isEmpty) return DateTime.now();
      try {
        // Handle DD/MM/YYYY HH:mm:ss
        if (dateStr.contains('/')) {
          final dateAndTime = dateStr.split(' ');
          final dateParts = dateAndTime[0].split('/');
          if (dateParts.length == 3) {
            final day = int.tryParse(dateParts[0]) ?? 1;
            final month = int.tryParse(dateParts[1]) ?? 1;
            final year = int.tryParse(dateParts[2]) ?? DateTime.now().year;

            if (dateAndTime.length > 1) {
              final timeParts = dateAndTime[1].split(':');
              if (timeParts.length >= 2) {
                return DateTime(
                  year,
                  month,
                  day,
                  int.tryParse(timeParts[0]) ?? 0,
                  int.tryParse(timeParts[1]) ?? 0,
                  timeParts.length > 2 ? (int.tryParse(timeParts[2]) ?? 0) : 0,
                );
              }
            }
            return DateTime(year, month, day);
          }
        }
        return DateTime.tryParse(dateStr) ?? DateTime.now();
      } catch (_) {
        return DateTime.now();
      }
    }

    return Trip(
      id: DateTime.now().millisecondsSinceEpoch
          .toString(), // Generate a local ID
      tripId: parseTripId(json['trips_id']),
      title: json['trip_name'] ?? 'Untitled Trip',
      description: json['purpose_of_visit'] ?? '',
      notes: json['notes'] ?? json['visit_notes'] ?? json['remarks'] ?? '',
      startAddress: json['from_location'] ?? '',
      endAddress: json['to_location'] ?? '',
      startLat: parseDouble(json['from_location_latitude']),
      startLng: parseDouble(json['from_location_longitude']),
      endLat: parseDouble(json['to_location_latitude']),
      endLng: parseDouble(json['to_location_longitude']),
      startTime: parseDate(json['created_date']),
      distanceKm: parseDouble(json['kilometer']),
      status: (json['trip_status'] ?? '').toString(),
      isActive: ![
        'complete',
        'completed',
        'finish',
        'finished',
      ].contains((json['trip_status'] ?? '').toString().toLowerCase().trim()),
    );
  }
}
