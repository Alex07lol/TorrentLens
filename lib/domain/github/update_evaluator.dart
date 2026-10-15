import '../manifests/source_manifest.dart';
import '../security/signatures.dart';
import 'semantic_version.dart';

enum UpdateStatus {
  upToDate,
  updateAvailable,
  /// A newer version exists but its publisher could not be verified. The UI
  /// must not offer an automatic install for this.
  updateAvailableUntrusted,
  downgrade,
  invalidVersions,
}

class UpdateDecision {
  final UpdateStatus status;
  final SemanticVersion? installed;
  final SemanticVersion? available;
  final bool installableWithoutPrompt;

  const UpdateDecision({
    required this.status,
    this.installed,
    this.available,
    this.installableWithoutPrompt = false,
  });

  bool get hasUpdate =>
      status == UpdateStatus.updateAvailable ||
      status == UpdateStatus.updateAvailableUntrusted;

  String get summary => switch (status) {
        UpdateStatus.upToDate => 'Up to date',
        UpdateStatus.updateAvailable => 'Update available: $available',
        UpdateStatus.updateAvailableUntrusted =>
          'Update $available available, publisher not verified',
        UpdateStatus.downgrade => 'Published version $available is older than $installed',
        UpdateStatus.invalidVersions => 'Could not compare versions',
      };
}

/// Decides whether a manifest represents a newer content version, and whether
/// it is safe to install automatically. Trust is a *precondition* for
/// `installableWithoutPrompt`; a checksum alone never qualifies.
class UpdateEvaluator {
  static UpdateDecision evaluate({
    required SourceManifest manifest,
    required TrustStatus trust,
    String? installedVersion,
  }) {
    final available = SemanticVersion.tryParse(manifest.contentVersion);
    if (available == null) {
      return const UpdateDecision(status: UpdateStatus.invalidVersions);
    }
    if (installedVersion == null || installedVersion.trim().isEmpty) {
      return UpdateDecision(
        status: UpdateStatus.updateAvailable,
        available: available,
        installableWithoutPrompt:
            trust.isTrusted && manifest.updatePolicy.autoDownload,
      );
    }
    final installed = SemanticVersion.tryParse(installedVersion);
    if (installed == null) {
      return UpdateDecision(
          status: UpdateStatus.invalidVersions, available: available);
    }

    final cmp = available.compareTo(installed);
    if (cmp == 0) {
      return UpdateDecision(
          status: UpdateStatus.upToDate, installed: installed, available: available);
    }
    if (cmp < 0) {
      return UpdateDecision(
          status: UpdateStatus.downgrade, installed: installed, available: available);
    }
    return UpdateDecision(
      status: trust.isTrusted
          ? UpdateStatus.updateAvailable
          : UpdateStatus.updateAvailableUntrusted,
      installed: installed,
      available: available,
      installableWithoutPrompt: trust.isTrusted && manifest.updatePolicy.autoDownload,
    );
  }
}
