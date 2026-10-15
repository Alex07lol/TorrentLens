import '../../domain/security/url_policy.dart';

/// The restrictions applied to untrusted HTML rendered inside the app.
///
/// Downloaded pages come from a torrent and are untrusted, so the sandbox is
/// deliberately locked down: JavaScript off by default, no file access, no
/// bridges, and every navigation is re-validated.
class WebSandboxPolicy {
  final bool javascriptEnabled;
  final bool allowExternalResourceLoading;
  final bool allowFileAccess;
  final bool allowInsecureContent;
  final int maxNavigations;

  const WebSandboxPolicy({
    this.javascriptEnabled = false,
    this.allowExternalResourceLoading = false,
    this.allowFileAccess = false,
    this.allowInsecureContent = false,
    this.maxNavigations = 50,
  });

  /// The default for any content that came from a torrent.
  static const WebSandboxPolicy untrusted = WebSandboxPolicy();

  /// Slightly relaxed profile a user can opt into, still without file access
  /// or JS bridges.
  static const WebSandboxPolicy trustedSite = WebSandboxPolicy(
    javascriptEnabled: true,
    allowExternalResourceLoading: true,
  );

  /// A page navigation is allowed only when it stays on http(s) and is not a
  /// private/loopback address. `about:blank` and fragment-only navigations are
  /// permitted so in-page anchors work.
  static bool allowsNavigation(String target, {Uri? current}) {
    final t = target.trim();
    if (t.isEmpty || t == 'about:blank' || t.startsWith('#')) return true;
    if (t.startsWith('javascript:') || t.startsWith('data:') || t.startsWith('file:')) {
      return false;
    }
    final uri = Uri.tryParse(t);
    if (uri == null) return false;
    if (!UrlPolicy.allowedSchemes.contains(uri.scheme.toLowerCase())) return false;
    if (uri.host.isEmpty) return current != null; // relative -> allowed in-page
    return !UrlPolicy.isPrivateHost(uri.host);
  }
}
