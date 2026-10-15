import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../../domain/security/archive_safety.dart';
import 'natural_order.dart';

class EpubChapter {
  final String id;
  final String title;
  final String href;
  final String text;
  const EpubChapter({required this.id, required this.title, required this.href, required this.text});
}

class EpubBook {
  final String title;
  final String? author;
  final String? language;
  final List<EpubChapter> chapters;
  /// Every non-spine resource (images, css, fonts) addressed by its zip path.
  final Map<String, List<int>> resources;
  const EpubBook({
    required this.title,
    this.author,
    this.language,
    required this.chapters,
    required this.resources,
  });

  String? resourceByName(String name) {
    if (resources.containsKey(name)) return name;
    final lower = name.toLowerCase();
    for (final k in resources.keys) {
      if (k.toLowerCase() == lower) return k;
    }
    return null;
  }
}

/// A small, dependency-light EPUB 2/3 parser.
///
/// It reads the OCF container, the OPF package document and the spine, and
/// extracts each spine document's text. Archive entries are validated by
/// [ArchiveSafety] before use, because an EPUB inside a torrent is untrusted.
class EpubParser {
  static const int maxEntries = 20000;
  static const int maxEntryBytes = 64 * 1024 * 1024;

  static EpubBook parse(List<int> bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (e) {
      throw const FormatException('That file is not a readable EPUB archive.');
    }

    final files = archive.files.where((f) => f.isFile).toList();
    if (files.length > maxEntries) {
      throw const FormatException('EPUB has too many entries.');
    }

    final map = <String, List<int>>{};
    for (final f in files) {
      final relative = ArchiveSafety.validateEntryName(f.name).valueOrNull;
      if (relative == null) continue; // hostile path -> skip
      final data = f.content;
      if (data.length > maxEntryBytes) continue;
      map[relative] = data;
    }

    final container = map['META-INF/container.xml'];
    if (container == null) {
      throw const FormatException('EPUB is missing META-INF/container.xml.');
    }
    final opfPath = _rootfilePath(container);
    if (opfPath == null || !map.containsKey(opfPath)) {
      throw const FormatException('EPUB package document could not be located.');
    }
    final opfDir = opfPath.contains('/') ? opfPath.substring(0, opfPath.lastIndexOf('/') + 1) : '';

    final XmlDocument opf;
    try {
      opf = XmlDocument.parse(utf8.decode(map[opfPath]!, allowMalformed: true));
    } catch (_) {
      throw const FormatException('EPUB package document is malformed.');
    }

    final title = _firstText(opf, 'title') ?? 'Untitled';
    final author = _firstText(opf, 'creator');
    final language = _firstText(opf, 'language');

    // manifest id -> href
    final manifest = <String, String>{};
    for (final item in opf.findAllElements('item')) {
      final id = item.getAttribute('id');
      final href = item.getAttribute('href');
      if (id != null && href != null) manifest[id] = href;
    }

    final spineIds = <String>[];
    for (final ref in opf.findAllElements('itemref')) {
      final idref = ref.getAttribute('idref');
      if (idref != null) spineIds.add(idref);
    }

    final tocTitles = _tocTitles(map, opfDir, opf);
    final chapters = <EpubChapter>[];
    for (final id in spineIds) {
      final href = manifest[id];
      if (href == null) continue;
      final path = _resolve(opfDir, href);
      final data = map[path];
      if (data == null) continue;
      final html = utf8.decode(data, allowMalformed: true);
      final text = htmlToPlainText(html);
      if (text.trim().isEmpty) continue;
      chapters.add(EpubChapter(
        id: id,
        title: tocTitles[path] ?? tocTitles[href] ?? _headingOf(html) ?? 'Chapter ${chapters.length + 1}',
        href: path,
        text: text,
      ));
    }
    if (chapters.isEmpty) {
      throw const FormatException('EPUB contains no readable chapters.');
    }

    final spineSet = {for (final c in chapters) c.href};
    final resources = <String, List<int>>{
      for (final e in map.entries)
        if (!spineSet.contains(e.key) && e.key != 'META-INF/container.xml' && e.key != opfPath) e.key: e.value,
    };

    return EpubBook(
      title: title,
      author: author,
      language: language,
      chapters: chapters,
      resources: resources,
    );
  }

  static String? _rootfilePath(List<int> containerXml) {
    try {
      final doc = XmlDocument.parse(utf8.decode(containerXml, allowMalformed: true));
      for (final el in doc.findAllElements('rootfile')) {
        final path = el.getAttribute('full-path');
        if (path != null && path.isNotEmpty) return path.replaceFirst(RegExp(r'^\./'), '');
      }
    } catch (_) {}
    return null;
  }

  /// Matches on the *local* name so namespaced elements such as `<dc:title>`
  /// are found regardless of the prefix the publisher used.
  static String? _firstText(XmlDocument doc, String localName) {
    for (final el in doc.descendantElements) {
      if (el.name.local != localName) continue;
      final t = el.innerText.trim();
      if (t.isNotEmpty) return t;
    }
    return null;
  }

  /// Titles from a nav document or an NCX, keyed by resolved href.
  static Map<String, String> _tocTitles(Map<String, List<int>> map, String opfDir, XmlDocument opf) {
    final titles = <String, String>{};
    // EPUB 3 nav
    for (final item in opf.findAllElements('item')) {
      final props = item.getAttribute('properties') ?? '';
      if (!props.split(' ').contains('nav')) continue;
      final href = item.getAttribute('href');
      if (href == null) continue;
      final data = map[_resolve(opfDir, href)];
      if (data == null) continue;
      try {
        final nav = XmlDocument.parse(utf8.decode(data, allowMalformed: true));
        for (final a in nav.findAllElements('a')) {
          final t = a.innerText.trim();
          final h = a.getAttribute('href');
          if (t.isNotEmpty && h != null) {
            titles[_resolve(_resolve(opfDir, href).contains('/') ? _resolve(opfDir, href).substring(0, _resolve(opfDir, href).lastIndexOf('/') + 1) : '', h.split('#').first)] = t;
          }
        }
      } catch (_) {}
    }
    // EPUB 2 NCX
    for (final item in opf.findAllElements('item')) {
      if ((item.getAttribute('media-type') ?? '') != 'application/x-dtbncx+xml') continue;
      final href = item.getAttribute('href');
      if (href == null) continue;
      final data = map[_resolve(opfDir, href)];
      if (data == null) continue;
      try {
        final ncx = XmlDocument.parse(utf8.decode(data, allowMalformed: true));
        for (final np in ncx.findAllElements('navPoint')) {
          final label = np.findAllElements('text').map((e) => e.innerText.trim()).firstWhere((t) => t.isNotEmpty, orElse: () => '');
          final src = np.findAllElements('content').map((e) => e.getAttribute('src')).firstWhere((s) => s != null, orElse: () => null);
          if (label.isNotEmpty && src != null) {
            titles[_resolve(opfDir, src.split('#').first)] = label;
          }
        }
      } catch (_) {}
    }
    return titles;
  }

  static String? _headingOf(String html) {
    final m = RegExp(r'<h[1-6][^>]*>(.*?)</h[1-6]>', caseSensitive: false, dotAll: true).firstMatch(html);
    if (m == null) return null;
    final text = htmlToPlainText(m.group(1) ?? '').trim();
    return text.isEmpty ? null : text;
  }

  static String _resolve(String base, String href) {
    final cleanHref = href.split('#').first;
    if (cleanHref.startsWith('/')) return cleanHref.substring(1);
    final segments = (base + cleanHref).split('/');
    final out = <String>[];
    for (final s in segments) {
      if (s.isEmpty || s == '.') continue;
      if (s == '..') {
        if (out.isNotEmpty) out.removeLast();
        continue;
      }
      out.add(s);
    }
    return out.join('/');
  }

  /// Strips markup to readable text, preserving paragraph breaks and converting
  /// block elements to newlines. Embedded scripts/styles are dropped.
  static String htmlToPlainText(String html) {
    var s = html;
    s = s.replaceAll(RegExp(r'<(script|style|head)[^>]*>.*?</\1>', caseSensitive: false, dotAll: true), ' ');
    s = s.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
    s = s.replaceAll(RegExp(r'</(p|div|h[1-6]|li|tr|blockquote)>', caseSensitive: false), '\n\n');
    s = s.replaceAll(RegExp(r'<li[^>]*>', caseSensitive: false), '• ');
    s = s.replaceAll(RegExp(r'<[^>]+>'), '');
    s = s
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&mdash;', '—')
        .replaceAll('&ndash;', '–')
        .replaceAll('&hellip;', '…')
        .replaceAll('&rsquo;', '’')
        .replaceAll('&lsquo;', '‘')
        .replaceAll('&ldquo;', '“')
        .replaceAll('&rdquo;', '”');
    s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return s.trim();
  }

  /// Kept for parity with the domain helper; natural ordering of chapter hrefs.
  static List<String> naturalSort(Iterable<String> names) => NaturalOrder.sorted(names);
}
