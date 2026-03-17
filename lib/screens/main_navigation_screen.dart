import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:trackersales/providers/auth_provider.dart';
import 'package:trackersales/providers/trip_provider.dart';
import 'package:trackersales/screens/home_screen.dart';
import 'package:trackersales/screens/future_trips_screen.dart';
import 'package:trackersales/screens/create_trip_screen.dart';
import 'package:trackersales/screens/trip_history_screen.dart';
import 'package:trackersales/screens/expense_screen.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:trackersales/utils/permission_util.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen>
    with WidgetsBindingObserver {
  int _selectedIndex = 0;
  bool _initializedIndex = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Re-verify mandatory permissions on resume even on Home screen
      PermissionUtil.checkMandatoryPermissions(context);
    }
  }

  Future<void> _fetchInitialData() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final tripProvider = Provider.of<TripProvider>(context, listen: false);

    if (authProvider.user != null) {
      await tripProvider.fetchTrips(authProvider.user!.systemUserId);
    }
  }

  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchInitialData();
      // Proactively check permissions on first load/arrival at Home Screen
      PermissionUtil.checkMandatoryPermissions(context);
    });

    // Auto-refresh timer: Fetch data every 30 seconds to keep app active
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) {
        _fetchInitialData();
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _onItemTapped(int index) async {
    // Check mandatory permissions on every tab tap as requested
    await PermissionUtil.checkMandatoryPermissions(context);

    if (index == 2) {
      // Check location permission before allowing trip creation
      var status = await Permission.location.status;

      if (!status.isGranted) {
        // First try to request normally
        status = await Permission.location.request();

        if (!status.isGranted) {
          if (mounted) {
            _showPermissionDialog();
          }
          return; // Stop navigation
        }
      }
    }

    setState(() {
      _selectedIndex = index;
    });
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.location_off_rounded, color: Colors.redAccent),
            SizedBox(width: 10),
            Text("Location Required"),
          ],
        ),
        content: const Text(
          "Trip tracking requires location access to work. Please allow location permission in settings to create a trip.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("Cancel", style: TextStyle(color: Colors.grey[600])),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              "Open Settings",
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_initializedIndex) {
      final args =
          ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      if (args != null && args.containsKey('initialIndex')) {
        _selectedIndex = args['initialIndex'];
      }
      _initializedIndex = true;
    }

    // Rebuild screens list on every build to ensure isActive is current
    final currentScreens = [
      HomeScreen(onSeeAll: () => _onItemTapped(3)),
      const FutureTripsScreen(),
      CreateTripScreen(isActive: _selectedIndex == 2),
      const TripHistoryScreen(),
      const ExpenseScreen(),
    ];

    return Scaffold(
      backgroundColor: Colors.white,
      body: IndexedStack(index: _selectedIndex, children: currentScreens),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 20,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: _onItemTapped,
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          selectedItemColor: Colors.black, // Uber-like
          unselectedItemColor: Colors.grey[400],
          showSelectedLabels: true,
          showUnselectedLabels: true,
          selectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 10,
            fontFamily: 'Poppins',
          ),
          unselectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 10,
            fontFamily: 'Poppins',
          ),
          elevation: 0,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_filled),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.calendar_month_rounded),
              label: 'Activity',
            ),
            BottomNavigationBarItem(
              icon: CircleAvatar(
                radius: 20,
                backgroundColor: Colors.black,
                child: Icon(Icons.add, color: Colors.white),
              ),
              label: '',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.history_rounded),
              label: 'History',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.receipt_long_rounded),
              label: 'Expenses',
            ),
          ],
        ),
      ),
    );
  }
}
