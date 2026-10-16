import 'package:flutter/services.dart';

/// Android's share sheet, over the small native channel in
/// `SystemSharePlugin.kt`. Returns false rather than throwing when no target
/// exists, so callers can say so instead of failing silently.
class SystemShare {
  static const MethodChannel _channel = MethodChannel('dev.torrentlens/system');

  static Future<bool> text(String text, {String? subject}) async {
    if (text.trim().isEmpty) return false;
    try {
      await _channel.invokeMethod<void>('share', {'text': text, 'subject': subject});
      return true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
