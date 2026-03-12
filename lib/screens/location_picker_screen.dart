import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:trackersales/theme/app_theme.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:trackersales/utils/constants.dart';

class PickedLocation {
  final LatLng latLng;
  final String address;

  PickedLocation({required this.latLng, required this.address});
}

class LocationPickerScreen extends StatefulWidget {
  final String title;
  final LatLng? initialLocation;

  const LocationPickerScreen({
    super.key,
    required this.title,
    this.initialLocation,
  });

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  LatLng? _pickedLocation;
  String _pickedAddress = "";
  final TextEditingController _searchController = TextEditingController();
  GoogleMapController? _mapController;
  bool _isLoading = true;
  bool _isSearching = false;
  List<dynamic> _searchResults = [];

  // API Key from constants
  final String _googleApiKey = AppConstants.googleMapsApiKey;

  @override
  void initState() {
    super.initState();
    _pickedLocation = widget.initialLocation;
    _determinePosition();
  }

  Future<void> _determinePosition() async {
    if (_pickedLocation != null) {
      _reverseGeocode(_pickedLocation!);
      setState(() => _isLoading = false);
      return;
    }

    try {
      Position position = await Geolocator.getCurrentPosition();
      final latLng = LatLng(position.latitude, position.longitude);
      if (mounted) {
        setState(() {
          _pickedLocation = latLng;
          _isLoading = false;
        });
        _mapController?.animateCamera(CameraUpdate.newLatLngZoom(latLng, 15));
        _reverseGeocode(latLng);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _pickedLocation = const LatLng(19.0760, 72.8777);
          _isLoading = false;
        });
        _reverseGeocode(const LatLng(19.0760, 72.8777));
      }
    }
  }

  Future<void> _reverseGeocode(LatLng location) async {
    try {
      final url = Uri.parse(
        "https://maps.googleapis.com/maps/api/geocode/json?latlng=${location.latitude},${location.longitude}&key=$_googleApiKey",
      );
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['results'].isNotEmpty) {
          setState(() {
            _pickedAddress = data['results'][0]['formatted_address'];
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Geocoding failed: $e")),
        );
      }
    }
  }

  Future<void> _searchLocation(String query) async {
    if (query.isEmpty) return;
    setState(() => _isSearching = true);
    try {
      final url = Uri.parse(
        "https://maps.googleapis.com/maps/api/place/textsearch/json?query=$query&key=$_googleApiKey",
      );
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _searchResults = data['results'];
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSearching = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Search failed: $e")),
        );
      }
    }
  }

  void _onResultTap(dynamic result) {
    final location = result['geometry']['location'];
    final latLng = LatLng(location['lat'], location['lng']);
    final address = result['formatted_address'] ?? result['name'];

    setState(() {
      _pickedLocation = latLng;
      _pickedAddress = address;
      _searchResults = [];
      _searchController.text = address;
    });

    _mapController?.animateCamera(CameraUpdate.newLatLngZoom(latLng, 16));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (_pickedLocation != null)
            IconButton(
              onPressed: () => Navigator.pop(
                context,
                PickedLocation(
                  latLng: _pickedLocation!,
                  address: _pickedAddress,
                ),
              ),
              icon: const Icon(Icons.check, color: AppTheme.primaryColor),
            ),
        ],
      ),
      body: Stack(
        children: [
          if (_isLoading)
            const Center(child: CircularProgressIndicator())
          else
            GoogleMap(
              initialCameraPosition: CameraPosition(
                target: _pickedLocation!,
                zoom: 15,
              ),
              onMapCreated: (controller) => _mapController = controller,
              onTap: (latLng) {
                setState(() {
                  _pickedLocation = latLng;
                });
                _reverseGeocode(latLng);
              },
              markers: _pickedLocation == null
                  ? {}
                  : {
                      Marker(
                        markerId: const MarkerId("picked"),
                        position: _pickedLocation!,
                        infoWindow: InfoWindow(title: _pickedAddress),
                      ),
                    },
            ),

          // Search UI
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Column(
              children: [
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: "Enter location name...",
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.my_location),
                        onPressed: () async {
                          Position position =
                              await Geolocator.getCurrentPosition();
                          LatLng current = LatLng(
                            position.latitude,
                            position.longitude,
                          );
                          _mapController?.animateCamera(
                            CameraUpdate.newLatLng(current),
                          );
                          setState(() {
                            _pickedLocation = current;
                          });
                          _reverseGeocode(current);
                        },
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                    onChanged: (val) {
                      if (val.length > 2) _searchLocation(val);
                    },
                  ),
                ),
                if (_searchResults.isNotEmpty)
                  Container(
                    constraints: const BoxConstraints(maxHeight: 300),
                    margin: const EdgeInsets.only(top: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: _searchResults.length,
                      separatorBuilder: (ctx, i) => const Divider(height: 1),
                      itemBuilder: (ctx, i) {
                        final res = _searchResults[i];
                        return ListTile(
                          leading: const Icon(Icons.location_on_outlined),
                          title: Text(res['name'] ?? ""),
                          subtitle: Text(
                            res['formatted_address'] ?? "",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => _onResultTap(res),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),

          // Confirmation Panel
          if (_pickedLocation != null && _searchResults.isEmpty)
            Positioned(
              bottom: 24,
              left: 16,
              right: 16,
              child: Card(
                elevation: 8,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.location_on, color: Colors.blue),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  "Confirm Location",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _pickedAddress.isEmpty
                                      ? "Finding address..."
                                      : _pickedAddress,
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(
                          context,
                          PickedLocation(
                            latLng: _pickedLocation!,
                            address: _pickedAddress,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 50),
                        ),
                        child: const Text("Use This Location"),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
