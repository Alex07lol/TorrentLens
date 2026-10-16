import '../../app/services.dart';
import '../../domain/github/update_evaluator.dart';
import '../../domain/models/subscription.dart';
import '../../integrations/github/update_checker.dart';

/// The result of checking one subscription: the updated record, what happened,
/// and whether the user should be told about it.
class SubscriptionCheckResult {
  final Subscription subscription;
  final UpdateCheckOutcome outcome;
  final String message;
  final bool hasUpdate;

  const SubscriptionCheckResult({
    required this.subscription,
    required this.outcome,
    required this.message,
    required this.hasUpdate,
  });
}

/// Checking a subscription and recording the outcome, in one place.
///
/// The Subscriptions screen and the background worker both need exactly this
/// behaviour — check, record the latest version/trust state/check timestamp,
/// describe any failure precisely — so it lives here rather than being written
/// twice and drifting. Neither caller decides what "verified" means: that comes
/// from the signature verifier through [UpdateCheckOutcome.trust].
class SubscriptionUpdateService {
  final AppServices services;
  SubscriptionUpdateService(this.services);

  Future<SubscriptionCheckResult> checkAndRecord(Subscription sub) async {
    final outcome = await services.updateChecker.check(
      owner: sub.owner,
      repo: sub.repo,
      installedVersion: sub.installedVersion,
    );
    final updated = sub.copyWith(
      latestVersion: outcome.manifest?.contentVersion ?? sub.latestVersion,
      trustStatus: outcome.trust.name,
      lastCheckedAtMs: DateTime.now().millisecondsSinceEpoch,
      manifestUrl: outcome.manifestUrl ?? sub.manifestUrl,
      magnetUri: outcome.manifest?.magnetUri ?? sub.magnetUri,
    );
    await services.subscriptions.upsert(updated);
    return SubscriptionCheckResult(
      subscription: updated,
      outcome: outcome,
      message: describe(outcome),
      hasUpdate: outcome.status == UpdateStatus.updateAvailable ||
          outcome.status == UpdateStatus.updateAvailableUntrusted,
    );
  }

  /// Every subscription whose stored interval has elapsed. A rate limit or a
  /// network failure still updates the timestamp, so a background check cannot
  /// turn into a request loop.
  Future<List<SubscriptionCheckResult>> checkDue({int? maxSubscriptions}) async {
    final due = await services.subscriptions
        .dueForCheck(DateTime.now().millisecondsSinceEpoch);
    final results = <SubscriptionCheckResult>[];
    for (final sub in due) {
      if (maxSubscriptions != null && results.length >= maxSubscriptions) break;
      try {
        results.add(await checkAndRecord(sub));
      } catch (e) {
        // Record the attempt so one broken repository cannot block the queue.
        await services.subscriptions.upsert(sub.copyWith(
          lastCheckedAtMs: DateTime.now().millisecondsSinceEpoch,
        ));
        results.add(SubscriptionCheckResult(
          subscription: sub,
          outcome: const UpdateCheckOutcome(status: UpdateStatus.invalidVersions),
          message: 'Check failed: $e',
          hasUpdate: false,
        ));
      }
    }
    return results;
  }

  /// A user-facing sentence for the outcome — the same text in the screen and
  /// in a notification, so the app never says two different things.
  static String describe(UpdateCheckOutcome outcome) => switch (outcome.error) {
        UpdateCheckError.rateLimited =>
          'GitHub rate limit reached. Add a token in Settings or try again later.',
        UpdateCheckError.noManifest => 'No manifest asset found in the latest releases.',
        UpdateCheckError.network => 'Network error while contacting GitHub.',
        UpdateCheckError.invalidManifest =>
          'The published manifest was rejected: ${outcome.message}',
        UpdateCheckError.noReleases => 'This repository has no releases.',
        UpdateCheckError.fetchFailed => 'Could not download the manifest asset.',
        null => outcome.message ?? '',
      };
}
