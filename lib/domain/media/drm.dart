import '../security/integrity.dart';

/// DRM systems we can *recognise*. Recognition is not support: playback still
/// requires a licensed device and authorised content access.
enum DrmSystem { widevine, playReady, clearKey, fairPlay, unknown }

class DrmIndicator {
  final DrmSystem system;
  final String evidence;
  const DrmIndicator(this.system, this.evidence);
}

class DrmAssessment {
  final bool isProtected;
  final List<DrmIndicator> indicators;
  /// True when the device's current playback stack could potentially play it
  /// *if* authorised. This never means "will play".
  final bool mayBePlayableIfAuthorized;
  final String explanation;

  const DrmAssessment({
    required this.isProtected,
    required this.indicators,
    required this.mayBePlayableIfAuthorized,
    required this.explanation,
  });
}

/// Recognises common protection metadata. It deliberately does **not** attempt
/// any license acquisition, key extraction or circumvention — it only reports
/// what the app would need in order to ask a provider for authorisation.
class DrmCapabilityDetector {
  static const Map<String, DrmSystem> _systemIds = {
    // Widevine
    'edef8ba9-79d6-4ace-a3c8-27dcd51d21ed': DrmSystem.widevine,
    // PlayReady
    '9a04f079-9840-4286-ab92-e65be0885f95': DrmSystem.playReady,
    // ClearKey / W3C common
    '1077efec-c0b2-4d02-ace3-3c1e52e2fb4b': DrmSystem.clearKey,
    // FairPlay (not available to ExoPlayer on Android)
    '94ce86fb-07ff-4f43-adb8-93d2fa968ca2': DrmSystem.fairPlay,
  };

  /// Scans manifest/segment text and headers for `ContentProtection` boxes or
  /// `pssh` UUIDs. Returns an assessment that the UI can show verbatim.
  static DrmAssessment assess({
    String? manifestText,
    Map<String, String>? headers,
  }) {
    final indicators = <DrmIndicator>[];
    final hay = (manifestText ?? '').toLowerCase();

    for (final entry in _systemIds.entries) {
      if (hay.contains(entry.key)) {
        indicators.add(DrmIndicator(entry.value, 'ContentProtection uuid ${entry.key}'));
      }
    }
    if (hay.contains('mp4protection')) {
      indicators.add(const DrmIndicator(DrmSystem.unknown, 'DASH mp4protection descriptor'));
    }
    if (hay.contains('widevine')) {
      indicators.add(const DrmIndicator(DrmSystem.widevine, 'mentioned by name'));
    }
    final ct = headers?['content-type']?.toLowerCase() ?? '';
    final cd = headers?['content-disposition']?.toLowerCase() ?? '';
    if (ct.contains('drm') || cd.contains('drm')) {
      indicators.add(const DrmIndicator(DrmSystem.unknown, 'DRM signalled in response headers'));
    }

    final systems = indicators.map((i) => i.system).toSet();
    final isProtected = systems.isNotEmpty;
    final androidSystems = systems.where(
        (s) => s == DrmSystem.widevine || s == DrmSystem.playReady || s == DrmSystem.clearKey);

    return DrmAssessment(
      isProtected: isProtected,
      indicators: indicators,
      mayBePlayableIfAuthorized: isProtected && androidSystems.isNotEmpty,
      explanation: isProtected
          ? 'This stream is protected by ${systems.map(_name).join(', ')}. '
              'TorrentLens can attempt playback only when the content provider '
              'authorises this device and the license server is reachable. It '
              'does not bypass protection.'
          : 'No protection metadata was detected.',
    );
  }

  /// Web-safe availability probe used by the player diagnostics screen.
  static bool get platformHasWidevine => true; // Android MediaDrm ships Widevine L3.

  static String _name(DrmSystem s) => switch (s) {
        DrmSystem.widevine => 'Widevine',
        DrmSystem.playReady => 'PlayReady',
        DrmSystem.clearKey => 'ClearKey',
        DrmSystem.fairPlay => 'FairPlay',
        DrmSystem.unknown => 'an unknown DRM system',
      };

  static String fingerprint(String manifestText) => Integrity.sha256Hex(manifestText.codeUnits);
}

/// The outcome of asking a content provider to authorise playback.
///
/// Only [authorized] permits playback to be attempted. Every other value is a
/// distinct, user-visible reason — never collapsed into a generic failure.
enum DrmAuthorizationOutcome {
  authorized,
  /// No provider adapter is configured, so authorisation cannot even be asked
  /// for. This is the default state of the app.
  providerNotConfigured,
  /// The provider refused this device/account.
  notAuthorized,
  /// The license server was unreachable or returned no license.
  licenseUnavailable,
  /// Access was granted before but the entitlement has lapsed.
  expired,
  /// The device playback stack cannot handle this protection system.
  unsupportedSystem,
}

/// Everything a provider needs in order to make an authorisation decision.
///
/// [headers] may carry an access token. It is deliberately excluded from
/// [DrmPlaybackRequest.describe] and from every log line: tokens must never be
/// written to logs.
class DrmPlaybackRequest {
  final Uri source;
  final DrmAssessment assessment;
  final Uri? licenseUrl;
  final String? assetId;
  final Map<String, String> headers;

  const DrmPlaybackRequest({
    required this.source,
    required this.assessment,
    this.licenseUrl,
    this.assetId,
    this.headers = const {},
  });

  /// A token-free description safe to display or log.
  String get describe =>
      '${source.scheme}://${source.host}${source.path}'
      ' [${assessment.indicators.map((i) => i.system.name).join(',')}]';
}

/// The result of an authorisation attempt.
class DrmAuthorizationResult {
  final DrmAuthorizationOutcome outcome;
  /// Short, user-facing explanation. Never contains credentials.
  final String message;
  /// The source the player may use once authorised (may differ from the request
  /// if the provider issues a signed playback URL). Null unless authorised.
  final Uri? authorizedSource;
  /// Headers the player must send with [authorizedSource]. Held in memory only.
  final Map<String, String> playbackHeaders;

  const DrmAuthorizationResult({
    required this.outcome,
    required this.message,
    this.authorizedSource,
    this.playbackHeaders = const {},
  });

  bool get canPlay => outcome == DrmAuthorizationOutcome.authorized;
}

/// The single boundary through which provider-authorised protected playback is
/// requested.
///
/// TorrentLens never acquires, extracts or manipulates licenses itself; an
/// implementation of this interface delegates that to a provider the user is
/// entitled to use. See docs/media-support.md.
abstract class AuthorizedPlaybackAdapter {
  /// Human-readable provider name, shown in diagnostics. Null when none.
  String? get providerName;

  Future<DrmAuthorizationResult> authorize(DrmPlaybackRequest request);
}

/// The default adapter: it refuses, honestly and immediately.
///
/// Nothing in the app pretends protected content will play. Wiring a real
/// provider means supplying a different [AuthorizedPlaybackAdapter].
class UnconfiguredAuthorizedPlaybackAdapter implements AuthorizedPlaybackAdapter {
  const UnconfiguredAuthorizedPlaybackAdapter();

  @override
  String? get providerName => null;

  @override
  Future<DrmAuthorizationResult> authorize(DrmPlaybackRequest request) async {
    return DrmAuthorizationResult(
      outcome: DrmAuthorizationOutcome.providerNotConfigured,
      message: 'No authorised-playback provider is configured for this '
          'content, so protected playback cannot be requested. Open the '
          'original source in its official app or browser instead.',
    );
  }
}
