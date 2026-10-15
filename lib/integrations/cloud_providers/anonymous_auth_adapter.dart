import '../../core/result.dart';
import '../../domain/cloud/cloud_contracts.dart';

/// No authentication (public read / anonymous write). Used by the mock provider
/// and by publishers that expose only public data.
class AnonymousAuthAdapter implements CloudAuthAdapter {
  @override
  String get method => 'none';
  @override
  bool get isAuthenticated => true;
  @override
  Future<Result<void>> signIn() async => const Ok(null);
  @override
  Future<void> signOut() async {}
}
