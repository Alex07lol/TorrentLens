import 'package:archive/archive.dart';

import '../../domain/security/archive_safety.dart';
import 'natural_order.dart';

/// Opens a CBZ (zip) comic archive and exposes its pages in natural order.
///
/// CBR/RAR is intentionally not handled here: there is no maintained,
/// permissively licensed pure-Dart RAR decoder, and running a non-free unrar
/// binary is out of scope. Callers surface that limitation explicitly.
class ComicArchive {
  static const Set<String> _imageExts = {
    '.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.avif', '.jxl'
  };
  static const int maxPages = 5000;

  final List<String> pages;
  final Map<String, ArchiveFile> _byName;

  ComicArchive._(this.pages, this._byName);

  static ComicArchive open(List<int> bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const FormatException('That archive could not be read as CBZ/ZIP.');
    }
    // A payload that is not really a ZIP decodes to an empty archive; treat
    // that as an invalid input so callers can distinguish it from "no images".
    if (archive.files.isEmpty) {
      throw const FormatException('That archive could not be read as CBZ/ZIP.');
    }
    final byName = <String, ArchiveFile>{};
    final names = <String>[];
    for (final f in archive.files) {
      if (!f.isFile) continue;
      final safe = ArchiveSafety.validateEntryName(f.name).valueOrNull;
      if (safe == null) continue;
      final dot = safe.lastIndexOf('.');
      if (dot < 0) continue;
      if (!_imageExts.contains(safe.substring(dot).toLowerCase())) continue;
      // Skip macOS resource forks and hidden files.
      if (safe.split('/').any((p) => p.startsWith('._') || p.startsWith('.'))) continue;
      byName[safe] = f;
      names.add(safe);
    }
    final sorted = NaturalOrder.sorted(names);
    if (sorted.length > maxPages) {
      throw const FormatException('This comic has too many pages to open safely.');
    }
    return ComicArchive._(sorted, byName);
  }

  int get length => pages.length;
  bool get isEmpty => pages.isEmpty;

  /// Raw bytes of a page. Reads on demand so a 500-page comic does not have to
  /// be held in memory all at once.
  List<int> pageBytes(int index) {
    final name = pages[index];
    final file = _byName[name];
    if (file == null) return const [];
    return file.content;
  }

  String pageName(int index) => pages[index];

  /// Supported only for directories that are already an image folder.
  static bool isImageFile(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0) return false;
    return _imageExts.contains(name.substring(dot).toLowerCase());
  }
}
