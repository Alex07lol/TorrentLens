import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The address field for a web tab: back, forward, the URL itself, reload and an
/// overflow menu for copy/share/external-open.
///
/// Validation is not done here — the caller runs [BrowserAddress.parse] and
/// shows the rejection, so the same rules apply to the address bar, the
/// new-tab page and any other entry point.
class AddressBar extends StatefulWidget {
  final String url;
  final bool loading;
  final bool canGoBack;
  final bool canGoForward;
  final bool insecure;
  final ValueChanged<String> onSubmit;
  final VoidCallback? onBack;
  final VoidCallback? onForward;
  final VoidCallback? onReload;
  final VoidCallback? onCopy;
  final VoidCallback? onShare;
  final VoidCallback? onOpenExternal;

  /// Copies text to the clipboard and reports it, so the caller can show a
  /// snack bar. Clipboard access is a UI concern, so the helper lives with the
  /// widget that offers the action.
  static Future<void> copy(BuildContext context, String text, String label) async {
    if (text.trim().isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(label)));
  }

  const AddressBar({
    super.key,
    required this.url,
    required this.onSubmit,
    this.loading = false,
    this.canGoBack = false,
    this.canGoForward = false,
    this.insecure = false,
    this.onBack,
    this.onForward,
    this.onReload,
    this.onCopy,
    this.onShare,
    this.onOpenExternal,
  });

  @override
  State<AddressBar> createState() => _AddressBarState();
}

class _AddressBarState extends State<AddressBar> {
  late final TextEditingController _controller;
  final FocusNode _focus = FocusNode();
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.url);
    _focus.addListener(() {
      if (_focus.hasFocus) {
        setState(() => _editing = true);
        _controller.selection = TextSelection(baseOffset: 0, extentOffset: _controller.text.length);
      } else {
        setState(() => _editing = false);
      }
    });
  }

  @override
  void didUpdateWidget(covariant AddressBar old) {
    super.didUpdateWidget(old);
    // Follow the page unless the user is typing in the field.
    if (!_editing && widget.url != old.url) {
      _controller.text = widget.url;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit(String value) {
    _focus.unfocus();
    widget.onSubmit(value);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 8, 4),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back',
            onPressed: widget.canGoBack ? widget.onBack : null,
            icon: const Icon(Icons.arrow_back),
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            tooltip: 'Forward',
            onPressed: widget.canGoForward ? widget.onForward : null,
            icon: const Icon(Icons.arrow_forward),
            visualDensity: VisualDensity.compact,
          ),
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.go,
              autocorrect: false,
              onSubmitted: _submit,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Address or search',
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
                prefixIcon: widget.insecure
                    ? Icon(Icons.lock_open, size: 18, color: scheme.error)
                    : Icon(Icons.lock_outline, size: 18, color: scheme.outline),
                prefixIconConstraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                suffixIcon: _editing
                    ? IconButton(
                        tooltip: 'Go',
                        icon: const Icon(Icons.arrow_forward, size: 18),
                        onPressed: () => _submit(_controller.text),
                      )
                    : null,
              ),
            ),
          ),
          IconButton(
            tooltip: widget.loading ? 'Reloading…' : 'Reload',
            onPressed: widget.onReload,
            icon: widget.loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            visualDensity: VisualDensity.compact,
          ),
          PopupMenuButton<String>(
            tooltip: 'Page actions',
            onSelected: (value) => switch (value) {
              'copy' => widget.onCopy?.call(),
              'share' => widget.onShare?.call(),
              'external' => widget.onOpenExternal?.call(),
              _ => null,
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'copy', child: ListTile(leading: Icon(Icons.copy), title: Text('Copy address'))),
              PopupMenuItem(value: 'share', child: ListTile(leading: Icon(Icons.share), title: Text('Share address'))),
              PopupMenuItem(
                  value: 'external',
                  child: ListTile(leading: Icon(Icons.open_in_browser), title: Text('Open in another browser'))),
            ],
          ),
        ],
      ),
    );
  }

}
