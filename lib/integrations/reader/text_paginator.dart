/// Splits a long document into pages suitable for a phone screen.
///
/// Pages break on paragraph boundaries where possible and never exceed
/// [targetChars] by more than a single long paragraph, so pagination is stable
/// (the same input always yields the same pages — important for resuming).
class TextPaginator {
  static List<String> paginate(String text, {int targetChars = 1600}) {
    final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final paragraphs = normalized.split(RegExp(r'\n{2,}'));
    final pages = <String>[];
    final buffer = StringBuffer();

    void flush() {
      final page = buffer.toString().trim();
      if (page.isNotEmpty) pages.add(page);
      buffer.clear();
    }

    for (final paragraph in paragraphs) {
      final trimmed = paragraph.trim();
      if (trimmed.isEmpty) continue;
      // A single huge paragraph is hard-split on sentence boundaries.
      if (trimmed.length > targetChars) {
        flush();
        for (final chunk in _splitLong(trimmed, targetChars)) {
          pages.add(chunk);
        }
        continue;
      }
      if (buffer.length + trimmed.length + 2 > targetChars && buffer.isNotEmpty) {
        flush();
      }
      if (buffer.isNotEmpty) buffer.write('\n\n');
      buffer.write(trimmed);
    }
    flush();
    return pages.isEmpty ? const [''] : pages;
  }

  static List<String> _splitLong(String paragraph, int target) {
    final out = <String>[];
    final sentences = paragraph.split(RegExp(r'(?<=[.!?])\s+'));
    final buffer = StringBuffer();
    for (final sentence in sentences) {
      if (buffer.length + sentence.length + 1 > target && buffer.isNotEmpty) {
        out.add(buffer.toString().trim());
        buffer.clear();
      }
      if (sentence.length > target) {
        // No sentence boundaries: hard chunk.
        for (var i = 0; i < sentence.length; i += target) {
          out.add(sentence.substring(i, (i + target).clamp(0, sentence.length)));
        }
        continue;
      }
      if (buffer.isNotEmpty) buffer.write(' ');
      buffer.write(sentence);
    }
    if (buffer.isNotEmpty) out.add(buffer.toString().trim());
    return out;
  }
}
