import '../../domain/cloud/cloud_contracts.dart';
import '../media_resolver/http_fetcher.dart';
import 'mock_cloud_provider.dart';
import 'rest_cloud_provider.dart';
import 'supabase_cloud_provider.dart';

/// Builds the cloud-provider registry with the built-in adapters.
///
/// The mock provider is only registered when explicitly requested (tests, and
/// the "try a provider" developer flow) so it can never be reached from a
/// manifest in a release build.
class CloudProviderRegistries {
  static CloudProviderRegistry standard({
    required HttpFetcher fetcher,
    bool includeMock = false,
    String? Function(String providerId)? supabaseAnonKey,
    String? Function()? supabaseAccessToken,
  }) {
    return CloudProviderRegistry([
      RestCloudProviderFactory(fetcher),
      if (supabaseAnonKey != null)
        SupabaseCloudProviderFactory(
            fetcher, supabaseAnonKey, supabaseAccessToken ?? () => null),
      if (includeMock) MockCloudProviderFactory(),
    ]);
  }
}
