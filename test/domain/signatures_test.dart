import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:torrentlens/domain/security/signatures.dart';
import 'package:torrentlens/domain/security/trusted_keys.dart';

void main() {
  final algo = Ed25519();
  late SimpleKeyPair keyPair;
  late List<int> publicKey;

  setUp(() async {
    keyPair = await algo.newKeyPair();
    publicKey = (await keyPair.extractPublicKey()).bytes;
  });

  InMemoryTrustedKeyRegistry registryWith({bool revoked = false}) =>
      InMemoryTrustedKeyRegistry([
        TrustedKey(keyId: 'k1', publisherId: 'pub1', publicKey: publicKey, revoked: revoked),
      ]);

  test('canonicalize is stable regardless of key order', () {
    final a = PublisherSignatureVerifier.canonicalize({'b': 2, 'a': {'y': 1, 'x': 2}});
    final b = PublisherSignatureVerifier.canonicalize({'a': {'x': 2, 'y': 1}, 'b': 2});
    expect(utf8.decode(a), utf8.decode(b));
  });

  test('verifies a genuine Ed25519 signature from a trusted key', () async {
    final msg = PublisherSignatureVerifier.canonicalize({'publisher': 'pub1', 'v': '1.0.0'});
    final sig = await algo.sign(msg, keyPair: keyPair);
    final res = await PublisherSignatureVerifier.verify(
      messageBytes: msg,
      signatureBase64: base64Encode(sig.bytes),
      keyId: 'k1',
      registry: registryWith(),
    );
    expect(res.status, TrustStatus.verified);
  });

  test('rejects a tampered message (content changed after signing)', () async {
    final msg = PublisherSignatureVerifier.canonicalize({'v': '1.0.0'});
    final sig = await algo.sign(msg, keyPair: keyPair);
    final tampered = PublisherSignatureVerifier.canonicalize({'v': '9.9.9'});
    final res = await PublisherSignatureVerifier.verify(
      messageBytes: tampered,
      signatureBase64: base64Encode(sig.bytes),
      keyId: 'k1',
      registry: registryWith(),
    );
    expect(res.status, TrustStatus.invalidSignature);
  });

  test('reports unknown publishers instead of trusting them', () async {
    final msg = PublisherSignatureVerifier.canonicalize({'v': '1'});
    final sig = await algo.sign(msg, keyPair: keyPair);
    final res = await PublisherSignatureVerifier.verify(
      messageBytes: msg,
      signatureBase64: base64Encode(sig.bytes),
      keyId: 'unknown-key',
      registry: InMemoryTrustedKeyRegistry(const []),
    );
    expect(res.status, TrustStatus.unknownPublisher);
  });

  test('reports a revoked key distinctly from an invalid signature', () async {
    final msg = PublisherSignatureVerifier.canonicalize({'v': '1'});
    final sig = await algo.sign(msg, keyPair: keyPair);
    final res = await PublisherSignatureVerifier.verify(
      messageBytes: msg,
      signatureBase64: base64Encode(sig.bytes),
      keyId: 'k1',
      registry: registryWith(revoked: true),
    );
    expect(res.status, TrustStatus.keyRevoked);
  });

  test('an unsigned manifest is unsigned, not verified', () async {
    final res = await PublisherSignatureVerifier.verify(
      messageBytes: const [1, 2, 3],
      signatureBase64: null,
      keyId: null,
      registry: registryWith(),
    );
    expect(res.status, TrustStatus.unsigned);
    expect(res.status.isTrusted, isFalse);
  });

  test('a malformed (non-64-byte) signature is rejected', () async {
    final res = await PublisherSignatureVerifier.verify(
      messageBytes: const [1, 2, 3],
      signatureBase64: base64Encode(const [1, 2, 3, 4]),
      keyId: 'k1',
      registry: registryWith(),
    );
    expect(res.status, TrustStatus.invalidSignature);
  });
}
