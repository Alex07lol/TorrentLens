/// A publisher's Ed25519 signing key, identified by a stable key id.
class TrustedKey {
  final String keyId;
  final String publisherId;
  /// Raw 32-byte Ed25519 public key.
  final List<int> publicKey;
  /// Set once a key is retired so old signatures can be reported as revoked
  /// rather than merely invalid.
  final bool revoked;

  const TrustedKey({
    required this.keyId,
    required this.publisherId,
    required this.publicKey,
    this.revoked = false,
  });
}

/// Where trusted publisher keys come from. Distribution is deliberately
/// pluggable: keys may be pinned in the app, configured by the user, or fetched
/// over HTTPS — but fetching them over the same channel as the manifest would
/// defeat the signature, so the default is a pinned, empty registry.
abstract class TrustedKeyRegistry {
  TrustedKey? lookup(String keyId);
  List<TrustedKey> keysForPublisher(String publisherId);
}

/// The default, deliberately-empty registry. An empty registry makes every
/// signed manifest report as [TrustStatus.unknownPublisher], which is the
/// fail-closed behaviour we want until real keys are provisioned.
class InMemoryTrustedKeyRegistry implements TrustedKeyRegistry {
  final Map<String, List<TrustedKey>> _byPublisher;
  final Map<String, TrustedKey> _byId;

  InMemoryTrustedKeyRegistry(List<TrustedKey> keys)
      : _byPublisher = {},
        _byId = {} {
    for (final k in keys) {
      _byId[k.keyId] = k;
      _byPublisher.putIfAbsent(k.publisherId, () => []).add(k);
    }
  }

  @override
  TrustedKey? lookup(String keyId) => _byId[keyId];

  @override
  List<TrustedKey> keysForPublisher(String publisherId) =>
      List.unmodifiable(_byPublisher[publisherId] ?? const <TrustedKey>[]);
}

/// The pinned keys shipped with the build. Populate this with your release key
/// before distributing: leaving it empty means every manifest is treated as
/// coming from an unknown publisher.
const List<TrustedKey> kPinnedPublisherKeys = <TrustedKey>[];
