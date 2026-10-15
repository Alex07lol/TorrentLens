import '../../domain/media/drm.dart';

/// Captures enough about a playback attempt to explain a failure honestly
/// rather than showing a generic "cannot play" message.
enum PlaybackFailureKind {
  network,
  httpStatus,
  unsupportedContainer,
  unsupportedCodec,
  drmUnauthorized,
  drmUnsupported,
  manifestInvalid,
  decodeError,
  unknown,
}

class PlaybackDiagnostics {
  final Uri? source;
  final String? mimeType;
  final int? httpStatus;
  final PlaybackFailureKind? failureKind;
  final String? rawMessage;
  final DrmAssessment? drm;
  final DateTime capturedAt;

  PlaybackDiagnostics({
    this.source,
    this.mimeType,
    this.httpStatus,
    this.failureKind,
    this.rawMessage,
    this.drm,
    DateTime? capturedAt,
  }) : capturedAt = capturedAt ?? DateTime.now();

  /// Human-readable explanation suitable for the diagnostics panel.
  String get explanation {
    switch (failureKind) {
      case PlaybackFailureKind.network:
        return 'The media could not be reached (network error or timeout).';
      case PlaybackFailureKind.httpStatus:
        return 'The server returned HTTP $httpStatus instead of media.';
      case PlaybackFailureKind.unsupportedContainer:
        return 'This container is not supported by the device playback stack.';
      case PlaybackFailureKind.unsupportedCodec:
        return 'The video/audio codec is not available on this device.';
      case PlaybackFailureKind.drmUnauthorized:
        return 'The stream is protected and this device is not authorised '
            '(no valid license). Playback cannot proceed without provider authorisation.';
      case PlaybackFailureKind.drmUnsupported:
        return 'The stream uses a DRM system this device cannot play.';
      case PlaybackFailureKind.manifestInvalid:
        return 'The HLS/DASH manifest was malformed or empty.';
      case PlaybackFailureKind.decodeError:
        return 'The decoder failed on this media.';
      case PlaybackFailureKind.unknown:
        return rawMessage ?? 'Playback failed for an unidentified reason.';
      case null:
        return 'No playback attempt recorded.';
    }
  }

  /// A fingerprint of the source, safe to show and log (no tokens/query).
  String get sourceLabel {
    final s = source;
    if (s == null) return '(no source)';
    return '${s.scheme}://${s.host}${s.path}';
  }
}
