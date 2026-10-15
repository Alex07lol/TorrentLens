import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'trusted_keys.dart';

/// Trust level for a publisher's content. Ordering matters: the UI shows this
/// verbatim, so each value has to be defensible on its own.
enum TrustStatus {
  /// No signature present at all.
  unsigned,
  /// A signature is present, but we have no key for the key id.
  unknownPublisher,
  /// Key found, but the key has been revoked.
  keyRevoked,
  /// Signature present and matched a trusted key.
  verified,
  /// Signature present, key found, but verification failed (tampered/wrong key).
  invalidSignature,
  /// A separate file-hash check failed after the signature was accepted.
  integrityFailed;

  bool get isTrusted => this == TrustStatus.verified;
  String get label => switch (this) {
        TrustStatus.unsigned => 'Unsigned',
        TrustStatus.unknownPublisher => 'Unknown publisher',
        TrustStatus.keyRevoked => 'Signing key revoked',
        TrustStatus.verified => 'Verified publisher',
        TrustStatus.invalidSignature => 'Invalid signature',
        TrustStatus.integrityFailed => 'Integrity check failed',
      };
}

class SignatureCheckResult {
  final TrustStatus status;
  final String? keyId;
  final String? detail;
  const SignatureCheckResult(this.status, {this.keyId, this.detail});
}

/// Ed25519 verification of publisher manifests.
///
/// The signed message is the canonical JSON of the manifest with the signature
/// block removed, exactly as produced by [canonicalize]: keys sorted, no
/// whitespace. This is what prevents a manifest from being altered in transit.
class PublisherSignatureVerifier {
  static final Ed25519 _ed25519 = Ed25519();

  /// Verifies [signatureBase64] over [messageBytes] using the key [keyId] from
  /// [registry]. Fail-closed: unknown keys and revoked keys never verify.
  static Future<SignatureCheckResult> verify({
    required List<int> messageBytes,
    required String? signatureBase64,
    required String? keyId,
    required TrustedKeyRegistry registry,
  }) async {
    if (signatureBase64 == null || signatureBase64.trim().isEmpty) {
      return const SignatureCheckResult(TrustStatus.unsigned);
    }
    if (keyId == null || keyId.trim().isEmpty) {
      return const SignatureCheckResult(TrustStatus.unknownPublisher,
          detail: 'signature present without a signing-key id');
    }
    final key = registry.lookup(keyId);
    if (key == null) {
      return SignatureCheckResult(TrustStatus.unknownPublisher,
          keyId: keyId, detail: 'no trusted key for key id $keyId');
    }
    if (key.revoked) {
      return SignatureCheckResult(TrustStatus.keyRevoked, keyId: keyId);
    }

    Uint8List sigBytes;
    try {
      sigBytes = base64Decode(signatureBase64.trim());
    } catch (_) {
      return SignatureCheckResult(TrustStatus.invalidSignature,
          keyId: keyId, detail: 'signature is not valid base64');
    }
    if (sigBytes.length != 64) {
      return SignatureCheckResult(TrustStatus.invalidSignature,
          keyId: keyId, detail: 'Ed25519 signature must be 64 bytes');
    }

    final publicKey = SimplePublicKey(key.publicKey, type: KeyPairType.ed25519);
    final signature = Signature(sigBytes, publicKey: publicKey);
    final ok = await _ed25519.verify(messageBytes, signature: signature);
    return SignatureCheckResult(
      ok ? TrustStatus.verified : TrustStatus.invalidSignature,
      keyId: keyId,
      detail: ok ? null : 'signature did not match the trusted key',
    );
  }

  /// Deterministic JSON used as the signed message. Sorts object keys
  /// recursively and emits no insignificant whitespace, so both publisher and
  /// client compute the same bytes.
  static List<int> canonicalize(Object? value) =>
      utf8.encode(_canonical(value));

  static String _canonical(Object? value) {
    if (value == null) return 'null';
    if (value is num || value is bool) return value.toString();
    if (value is String) return jsonEncode(value);
    if (value is List) return '[${value.map(_canonical).join(',')}]';
    if (value is Map) {
      final keys = value.keys.map((e) => e.toString()).toList()..sort();
      return '{${keys.map((k) => '${jsonEncode(k)}:${_canonical(value[k])}').join(',')}}';
    }
    return jsonEncode(value.toString());
  }
}
