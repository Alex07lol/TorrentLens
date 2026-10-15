import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../app/providers.dart';
import '../../design_system/components.dart';
import '../../integrations/media_resolver/media_link_resolver.dart';
import '../../integrations/media_resolver/web_content_sandbox.dart';
import '../../navigation/route_args.dart';
import '../media_resolver/discovered_resources_sheet.dart';

/// Sandboxed viewer for HTML that shipped inside a torrent (or any web page).
///
/// Defaults: JavaScript OFF, no JavaScript channels registered, no file access
/// beyond the loaded document, and every navigation re-validated. Turning
/// JavaScript on is per-page and shows a warning.
class WebSandboxScreen extends ConsumerStatefulWidget {
  final WebSandboxArgs args;
  const WebSandboxScreen({super.key, required this.args});
  @override
  ConsumerState<WebSandboxScreen> createState() => _WebSandboxScreenState();
}

class _WebSandboxScreenState extends ConsumerState<WebSandboxScreen> {
  late final WebViewController _controller;
  late bool _javascript;
  bool _loading = true;
  String? _error;
  String _currentUrl = '';

  @override
  void initState() {
    super.initState();
    _javascript = widget.args.allowJavascript;
    _controller = WebViewController()
      ..setJavaScriptMode(_javascript ? JavaScriptMode.unrestricted : JavaScriptMode.disabled)
      ..setBackgroundColor(const Color(0xFF101418))
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (request) {
          if (!WebSandboxPolicy.allowsNavigation(request.url, current: Uri.tryParse(_currentUrl))) {
            _blocked(request.url);
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
        onPageStarted: (url) => setState(() {
          _loading = true;
          _currentUrl = url;
        }),
        onPageFinished: (url) => setState(() => _loading = false),
        onWebResourceError: (error) => setState(() {
          _loading = false;
          _error = error.description;
        }),
      ));
    _load();
  }

  void _blocked(String url) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Blocked a navigation to an unsafe destination: $url'),
    ));
  }

  Future<void> _load() async {
    try {
      if (widget.args.localHtmlPath != null) {
        await _controller.loadFile(widget.args.localHtmlPath!);
      } else if (widget.args.url != null) {
        await _controller.loadRequest(widget.args.url!);
      } else {
        throw Exception('No page to display.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.args.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: _javascript ? 'Disable JavaScript' : 'Enable JavaScript (reloads)',
            onPressed: _toggleJavascript,
            icon: Icon(_javascript ? Icons.code : Icons.code_off),
          ),
          IconButton(
            tooltip: 'Find media links on this page',
            onPressed: _findResources,
            icon: const Icon(Icons.travel_explore),
          ),
          IconButton(
            tooltip: 'Open in browser',
            onPressed: () => _openInBrowser(_currentUrl),
            icon: const Icon(Icons.open_in_browser),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: Theme.of(context).colorScheme.errorContainer,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text(
              _javascript
                  ? 'Untrusted content — JavaScript is ENABLED for this page. Only do this for pages you trust.'
                  : 'Untrusted content — JavaScript is disabled. Scripts cannot run.',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: _error != null && !_loading
                ? ErrorView(message: _error!, onRetry: () => setState(() { _error = null; _load(); }))
                : WebViewWidget(controller: _controller),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleJavascript() async {
    final enable = !_javascript;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(enable ? 'Enable JavaScript?' : 'Disable JavaScript?'),
        content: Text(enable
            ? 'This page came from a torrent and is untrusted. Enabling JavaScript lets its '
                'code run inside the viewer sandbox (still with no app bridges and no file APIs).'
            : 'The page will reload without JavaScript.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Continue')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _javascript = enable);
    await _controller.setJavaScriptMode(enable ? JavaScriptMode.unrestricted : JavaScriptMode.disabled);
    await _controller.reload();
  }

  Future<void> _openInBrowser(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (!WebSandboxPolicy.allowsNavigation(url)) {
      _blocked(url);
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// Runs the Media Link Resolver *without* executing page scripts: for local
  /// bundles we read the file, for remote pages we fetch the HTML ourselves.
  Future<void> _findResources() async {
    try {
      final services = ref.read(servicesProvider);
      LinkResolutionResult result;
      if (widget.args.localHtmlPath != null) {
        final html = await File(widget.args.localHtmlPath!).readAsString();
        result = services.resolver.resolveFromHtml(
          html: html,
          baseUrl: Uri.file(widget.args.localHtmlPath!),
        );
      } else if (widget.args.url != null) {
        final fetched = await services.resolver.resolveFromUrl(widget.args.url!.toString());
        if (fetched.isErr) {
          throw Exception('${fetched.errorOrNull()}');
        }
        result = fetched.valueOrNull!;
      } else {
        throw Exception('Nothing to analyse.');
      }
      if (!mounted) return;
      await showDiscoveredResources(context, result, pageTitle: widget.args.title);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not analyse the page: $e')));
    }
  }
}
