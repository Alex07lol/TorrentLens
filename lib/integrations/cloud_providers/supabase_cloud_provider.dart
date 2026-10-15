import '../../core/result.dart';
import '../../domain/cloud/cloud_contracts.dart';
import '../media_resolver/http_fetcher.dart';
import 'rest_cloud_provider.dart';

/// Supabase adapter.
///
/// Supabase exposes a PostgREST API, so this is [RestCloudProvider] with the
/// project's **public** anon key sent as `apikey` (and, when signed in, the
/// user's access token as a bearer token). Row Level Security is the real
/// boundary: the service-role key must never ship in the APK and is never read
/// by this code.
class SupabaseCloudProviderFactory implements CloudProviderFactory {
  final HttpFetcher fetcher;
  /// Resolved at runtime from secure storage — never baked into the APK.
  final String? Function(String providerId) anonKeyProvider;
  final String? Function() accessTokenProvider;

  SupabaseCloudProviderFactory(this.fetcher, this.anonKeyProvider, this.accessTokenProvider);

  @override
  String get providerType => 'supabase';

  @override
  Result<CloudProvider> create(PublisherConfig config, CloudAuthAdapter auth) {
    final key = anonKeyProvider(config.publisherIdentity ?? config.endpoint.host);
    if (key == null || key.isEmpty) {
      return const Err('Supabase anon key is not configured; add it in Settings -> Cloud');
    }
    final token = accessTokenProvider();
    return Ok(RestCloudProvider(fetcher, config, auth, extraHeaders: {
      'apikey': key,
      'accept': 'application/json',
      if (token != null && token.isNotEmpty) 'authorization': 'Bearer $token',
    }));
  }
}
