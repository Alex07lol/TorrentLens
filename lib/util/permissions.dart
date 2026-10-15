import 'dart:io';
import 'package:permission_handler/permission_handler.dart';

/// Thin wrapper so permission rationale text lives in one place and every
/// request is paired with an explanation shown to the user first.
class AppPermissions {
  /// Why each permission is requested, shown in the UI.
  static const Map<String, String> rationale = {
    'notifications':
        'Shows transfer progress and lets you know when a subscribed publisher publishes a new version.',
  };

  static Future<bool> notificationsGranted() async {
    if (!Platform.isAndroid) return true;
    return Permission.notification.isGranted;
  }

  /// Requests POST_NOTIFICATIONS on Android 13+. Returns whether it is granted.
  static Future<bool> requestNotifications() async {
    if (!Platform.isAndroid) return true;
    final current = await Permission.notification.status;
    if (current.isGranted) return true;
    final result = await Permission.notification.request();
    return result.isGranted;
  }

  static Future<void> openSettings() => openAppSettings();
}
