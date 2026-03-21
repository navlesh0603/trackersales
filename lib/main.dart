import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:trackersales/providers/auth_provider.dart';
import 'package:trackersales/providers/trip_provider.dart';
import 'package:trackersales/providers/notification_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:trackersales/screens/change_password_screen.dart';
import 'package:trackersales/screens/create_trip_screen.dart';
import 'package:trackersales/screens/forgot_password_screen.dart';
import 'package:trackersales/screens/future_trips_screen.dart';
import 'package:trackersales/screens/login_screen.dart';
import 'package:trackersales/screens/main_navigation_screen.dart';
import 'package:trackersales/screens/trip_tracking_screen.dart';
import 'package:trackersales/services/background_service.dart';
import 'package:trackersales/theme/app_theme.dart';

import 'package:trackersales/screens/notifications_screen.dart';
import 'package:trackersales/screens/attendance_screen.dart';
import 'package:trackersales/screens/check_in_out_screen.dart';

import 'package:flutter/foundation.dart';
import 'dart:io';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Only initialize background service on mobile platforms
  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    await initializeService();

    // Auto-resume background service if a trip was active
    final prefs = await SharedPreferences.getInstance();
    final activeTripId = prefs.getString('active_trip_id');
    if (activeTripId != null) {
      final service = FlutterBackgroundService();
      if (!(await service.isRunning())) {
        await service.startService();
      }
    }
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => TripProvider()),
        ChangeNotifierProvider(create: (_) => NotificationProvider()),
      ],
      child: const MainApp(),
    ),
  );
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, _) {
        return MaterialApp(
          title: 'Trackersales',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          // We show a loader while checking auth status, then decide between home and login
          home: authProvider.isInitializing
              ? const Scaffold(body: Center(child: CircularProgressIndicator()))
              : (authProvider.isAuthenticated
                    ? const MainNavigationScreen()
                    : const LoginScreen()),
          routes: {
            '/login': (context) => const LoginScreen(),
            '/home': (context) => const MainNavigationScreen(),
            '/create_trip': (context) => const CreateTripScreen(),
            '/tracking': (context) => const TripTrackingScreen(),
            '/calendar': (context) => const FutureTripsScreen(),
            '/change_password': (context) => const ChangePasswordScreen(),
            '/forgot-password': (context) => const ForgotPasswordScreen(),
            '/notifications': (context) => const NotificationsScreen(),
            '/attendance': (context) => const AttendanceScreen(),
            '/check-in-out': (context) => const CheckInOutScreen(),
          },
        );
      },
    );
  }
}
