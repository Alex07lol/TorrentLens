import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';

import '../../app/services.dart';
import 'subscription_update_service.dart';

/// The deferred update check.
///
/// This is *deferrable* work: it is fine if Android runs it late, and it must
/// never be used for transfers. The app previously declared the `workmanager`
/// dependency, documented periodic checks, and never registered anything — so
/// nothing was ever scheduled. This file is the missing registration.
///
/// Everything Android-specific is guarded: model updates are never reported as
/// verified here (the signature verifier decides that), and a failure returns
/// `false` so WorkManager retries with backoff instead of silently giving up.
const String kUpdateCheckTask = 'dev.torrentlens.subscriptionUpdateCheck';
const String kUpdateCheckUniqueName = 'dev.torrentlens.subscriptionUpdateCheck.periodic';

/// Android's own floor for periodic work is 15 minutes; 6 hours is a sane
/// balance between freshness and rate limits (unauthenticated GitHub API calls
/// are limited to 60/hour per IP).
const Duration kUpdateCheckFrequency = Duration(hours: 6);

const String kUpdateChannelId = 'dev.torrentlens.updates';
const String kUpdateChannelName = 'Publisher updates';

@pragma('vm:entry-point')
void updateCheckDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task != kUpdateCheckTask) return true;
    try {
      await runUpdateCheck();
      return true;
    } catch (e) {
      debugPrint('TorrentLens: background update check failed: $e');
      return false;
    }
  });
}

/// Performs one pass over every subscription that is due.
///
/// Returns the results so the caller (and tests) can inspect what was found.
Future<List<SubscriptionCheckResult>> runUpdateCheck({
  AppServices? services,
  Future<void> Function(List<SubscriptionCheckResult> results)? notify,
}) async {
  final s = services ?? await AppServices.open();
  try {
    final results = await SubscriptionUpdateService(s).checkDue();
    final updates = results.where((r) => r.hasUpdate).toList();
    if (updates.isNotEmpty) {
      await (notify ?? (r) => PublisherUpdateNotifications.show(r))(updates);
    }
    return results;
  } finally {
    if (services == null) await s.dispose();
  }
}

/// Registers (or re-registers) the periodic check. Safe to call on every start:
/// unique periodic work replaces the previous definition.
class UpdateCheckScheduler {
  static Future<bool> ensureScheduled() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      await Workmanager().initialize(updateCheckDispatcher);
      await Workmanager().registerPeriodicTask(
        kUpdateCheckUniqueName,
        kUpdateCheckTask,
        frequency: kUpdateCheckFrequency,
        constraints: Constraints(networkType: NetworkType.connected),
        backoffPolicy: BackoffPolicy.exponential,
        backoffPolicyDelay: const Duration(minutes: 30),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
        tag: 'torrentlens-updates',
      );
      return true;
    } catch (e) {
      // A device that refuses background work must not stop the app starting;
      // manual checks keep working.
      debugPrint('TorrentLens: could not schedule the update check: $e');
      return false;
    }
  }

  static Future<void> cancel() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await Workmanager().cancelByUniqueName(kUpdateCheckUniqueName);
    } catch (_) {
      // Nothing scheduled: nothing to cancel.
    }
  }
}

/// The notification shown when a publisher has something newer.
///
/// It says only what was actually verified: the version from the manifest and
/// the trust state the signature verifier reported. It never offers to install
/// anything by itself.
class PublisherUpdateNotifications {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  /// Never throws. A notification that cannot be posted (no plugin registered in
  /// the background isolate, a device with notifications disabled) must not turn
  /// a successful check into a failed job that WorkManager retries forever.
  static Future<bool> show(List<SubscriptionCheckResult> updates) async {
    try {
      return await _show(updates);
    } catch (e) {
      debugPrint('TorrentLens: could not post the update notification: $e');
      return false;
    }
  }

  static Future<bool> _show(List<SubscriptionCheckResult> updates) async {
    if (!_ready) {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      _ready = true;
    }
    if (updates.length == 1) {
      final r = updates.single;
      await _plugin.show(
        id: _idFor(r.subscription.id),
        title: 'Update: ${r.subscription.title}',
        body: '${r.subscription.latestVersion ?? 'A new release'} is available '
            '(publisher: ${r.outcome.trust.name}). Open Subscriptions to review it.',
        notificationDetails: _details(),
        payload: r.subscription.id,
      );
      return true;
    }
    await _plugin.show(
      id: _idFor('all'),
      title: '${updates.length} publisher updates',
      body: updates
          .map((r) => '${r.subscription.title}: ${r.subscription.latestVersion ?? 'new release'}')
          .join('\n'),
      notificationDetails: _details(),
    );
    return true;
  }

  static NotificationDetails _details() => const NotificationDetails(
        android: AndroidNotificationDetails(
          kUpdateChannelId,
          kUpdateChannelName,
          channelDescription: 'New releases from subscribed publishers',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      );

  static int _idFor(String key) => 0x70000000 | (key.hashCode & 0x00FFFFFF);
}
