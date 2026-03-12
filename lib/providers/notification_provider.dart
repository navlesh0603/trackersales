import 'package:flutter/material.dart';

class NotificationItem {
  final String title;
  final String message;
  final DateTime time;
  bool isRead;

  NotificationItem({
    required this.title,
    required this.message,
    required this.time,
    this.isRead = false,
  });
}

class NotificationProvider with ChangeNotifier {
  final List<NotificationItem> _notifications = [
    NotificationItem(
      title: "Welcome to Trackersales",
      message: "Ready to track your first sales journey? Start now!",
      time: DateTime.now().subtract(const Duration(minutes: 10)),
    ),
  ];

  List<NotificationItem> get notifications =>
      List.unmodifiable(_notifications.reversed);
  int get unreadCount => _notifications.where((n) => !n.isRead).length;

  void addNotification(String title, String message) {
    _notifications.add(
      NotificationItem(title: title, message: message, time: DateTime.now()),
    );
    notifyListeners();
  }

  void markAllAsRead() {
    for (var n in _notifications) {
      n.isRead = true;
    }
    notifyListeners();
  }

  void clearAll() {
    _notifications.clear();
    notifyListeners();
  }
}
