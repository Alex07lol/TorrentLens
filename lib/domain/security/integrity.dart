import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// Content integrity helpers. Integrity proves the *bytes* were not corrupted;
/// it does not prove *who* published them (that is [PublisherSignatureVerifier]).
class Integrity {
  /// Streams [bytes] through SHA-256 and returns lowercase hex.
  static String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

  /// Convenience for files read in chunks without loading everything in memory.
  static String sha256OfData(List<int> data) => sha256.convert(data).toString();

  /// Constant-time comparison of an expected hash against a computed one.
  /// Accepts `sha256:<hex>` prefixes. Never short-circuits, so it does not
  /// leak how many leading characters matched.
  static bool matchesSha256(List<int> bytes, String expected) {
    var exp = expected.trim().toLowerCase();
    if (exp.startsWith('sha256:')) exp = exp.substring(7);
    if (exp.isEmpty) return false;
    final actual = sha256Hex(bytes);
    return constantTimeHexEquals(actual, exp);
  }

  static bool constantTimeHexEquals(String a, String b) {
    final ab = a.trim().toLowerCase();
    final bb = b.trim().toLowerCase();
    if (ab.length != bb.length) return false;
    var diff = 0;
    for (var i = 0; i < ab.length; i++) {
      diff |= ab.codeUnitAt(i) ^ bb.codeUnitAt(i);
    }
    return diff == 0;
  }

  static String base64Of(List<int> bytes) => base64Encode(bytes);
  static Uint8List fromBase64(String s) => base64Decode(s);
}
