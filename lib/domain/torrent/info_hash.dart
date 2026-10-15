/// A BitTorrent v1 info-hash: exactly 20 bytes.
///
/// Accepts the two textual encodings used in magnet links and `.torrent`
/// bencode: lowercase/uppercase hex (40 chars) and RFC 4648 base32 (32 chars).
class InfoHash {
  static const int length = 20;

  final List<int> bytes;

  InfoHash._(this.bytes) {
    if (bytes.length != length) {
      throw ArgumentError('info-hash must be $length bytes, got ${bytes.length}');
    }
  }

  factory InfoHash.fromBytes(List<int> value) => InfoHash._(List<int>.unmodifiable(value));

  /// Parses a hex (40 char) or base32 (32 char) info-hash. Returns null when
  /// the input is not a valid encoding of a 20-byte digest.
  static InfoHash? tryParse(String raw) {
    final s = raw.trim();
    if (s.length == 40 && _isHex(s)) {
      return InfoHash._(_hexToBytes(s));
    }
    if (s.length == 32 && _isBase32(s)) {
      final decoded = _base32Decode(s);
      if (decoded.length == length) return InfoHash._(decoded);
    }
    return null;
  }

  String toHex() => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  static bool _isHex(String s) => RegExp(r'^[0-9a-fA-F]{40}$').hasMatch(s);
  static bool _isBase32(String s) => RegExp(r'^[A-Za-z2-7]{32}$').hasMatch(s);

  static List<int> _hexToBytes(String s) {
    final out = <int>[];
    for (var i = 0; i < s.length; i += 2) {
      out.add(int.parse(s.substring(i, i + 2), radix: 16));
    }
    return out;
  }

  static const String _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

  static List<int> _base32Decode(String input) {
    final s = input.toUpperCase();
    var buffer = 0;
    var bits = 0;
    final out = <int>[];
    for (final ch in s.split('')) {
      final v = _alphabet.indexOf(ch);
      if (v < 0) return const <int>[];
      buffer = (buffer << 5) | v;
      bits += 5;
      if (bits >= 8) {
        bits -= 8;
        out.add((buffer >> bits) & 0xff);
      }
    }
    return out;
  }

  @override
  bool operator ==(Object other) {
    if (other is! InfoHash) return false;
    for (var i = 0; i < length; i++) {
      if (bytes[i] != other.bytes[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(bytes);

  @override
  String toString() => toHex();
}
