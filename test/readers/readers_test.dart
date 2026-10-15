import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:torrentlens/domain/media/subtitles.dart';
import 'package:torrentlens/integrations/reader/comic_source.dart';
import 'package:torrentlens/integrations/reader/epub_parser.dart';
import 'package:torrentlens/integrations/reader/natural_order.dart';
import 'package:torrentlens/integrations/reader/text_paginator.dart';

List<int> zipOf(Map<String, String> entries) {
  final archive = Archive();
  entries.forEach((name, content) => archive.addFile(ArchiveFile.string(name, content)));
  return ZipEncoder().encode(archive);
}

void main() {
  group('NaturalOrder', () {
    test('sorts numerically, not lexically', () {
      final sorted = NaturalOrder.sorted(['page10.jpg', 'page2.jpg', 'page1.jpg']);
      expect(sorted, ['page1.jpg', 'page2.jpg', 'page10.jpg']);
    });

    test('is case-insensitive and stable for equal keys', () {
      expect(NaturalOrder.compare('Chapter2', 'chapter10') < 0, isTrue);
      expect(NaturalOrder.compare('a', 'a'), 0);
    });
  });

  group('TextPaginator', () {
    test('keeps pages within the target and preserves paragraph breaks', () {
      final paragraph = ('word ' * 100).trim();
      final text = List.generate(20, (_) => paragraph).join('\n\n');
      final pages = TextPaginator.paginate(text, targetChars: 1000);
      expect(pages.length, greaterThan(1));
      for (final p in pages) {
        expect(p.length, lessThanOrEqualTo(1300));
      }
      expect(pages.first.contains('word word'), isTrue);
    });

    test('is deterministic for the same input', () {
      final text = ('Sentence one. Sentence two. ' * 200);
      expect(TextPaginator.paginate(text), TextPaginator.paginate(text));
    });

    test('splits a single oversized paragraph on sentence boundaries', () {
      final long = List.generate(200, (i) => 'Sentence number $i.').join(' ');
      final pages = TextPaginator.paginate(long, targetChars: 200);
      expect(pages.length, greaterThan(1));
      expect(pages.every((p) => p.length <= 260), isTrue);
    });

    test('empty input yields a single empty page rather than nothing', () {
      expect(TextPaginator.paginate('   '), ['']);
    });
  });

  group('SubtitleTrack', () {
    const srt = '''
1
00:00:01,000 --> 00:00:03,500
Hello <i>world</i>

2
00:00:04,000 --> 00:00:06,000
Second line
''';
    test('parses SRT cues and strips inline tags', () {
      final track = SubtitleTrack.parse(srt);
      expect(track.format, 'srt');
      expect(track.cues.length, 2);
      expect(track.cues.first.text, 'Hello world');
      expect(track.cueAt(2000)!.text, 'Hello world');
      expect(track.cueAt(3800), isNull);
      expect(track.cueAt(5000)!.text, 'Second line');
    });

    test('parses WebVTT', () {
      const vtt = '''WEBVTT

00:00:00.500 --> 00:00:02.000
First cue

00:00:02.000 --> 00:00:04.000
Second cue
''';
      final track = SubtitleTrack.parse(vtt);
      expect(track.format, 'vtt');
      expect(track.cues.length, 2);
      expect(track.cueAt(1000)!.text, 'First cue');
    });

    test('malformed input yields no cues instead of throwing', () {
      expect(SubtitleTrack.parse('not a subtitle file').cues, isEmpty);
    });
  });

  group('EpubParser', () {
    List<int> minimalEpub({String? container = 'yes'}) => zipOf({
          if (container != null)
            'META-INF/container.xml': '''
<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>''',
          'OEBPS/content.opf': '''
<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>Test Book</dc:title>
    <dc:creator>Ada Lovelace</dc:creator>
    <dc:language>en</dc:language>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="c1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
    <item id="c2" href="chapter2.xhtml" media-type="application/xhtml+xml"/>
    <item id="css" href="style.css" media-type="text/css"/>
  </manifest>
  <spine><itemref idref="c1"/><itemref idref="c2"/></spine>
</package>''',
          'OEBPS/nav.xhtml': '''
<html xmlns="http://www.w3.org/1999/xhtml"><body><nav><ol>
<li><a href="chapter1.xhtml">Chapter One</a></li>
<li><a href="chapter2.xhtml">Chapter Two</a></li>
</ol></nav></body></html>''',
          'OEBPS/chapter1.xhtml':
              '<html><body><h1>One</h1><p>First &amp; best paragraph.</p><script>evil()</script></body></html>',
          'OEBPS/chapter2.xhtml': '<html><body><p>Second paragraph.</p></body></html>',
          'OEBPS/style.css': 'body { color: red; }',
        });

    test('reads title, author, spine order and chapter text', () {
      final book = EpubParser.parse(minimalEpub());
      expect(book.title, 'Test Book');
      expect(book.author, 'Ada Lovelace');
      expect(book.chapters.length, 2);
      expect(book.chapters.first.text.contains('First & best paragraph.'), isTrue);
      expect(book.chapters.first.text.contains('evil()'), isFalse); // scripts stripped
      expect(book.chapters.first.title, 'Chapter One'); // from the nav document
      expect(book.resources.keys.any((k) => k.endsWith('style.css')), isTrue);
    });

    test('rejects an archive without a container', () {
      expect(() => EpubParser.parse(minimalEpub(container: null)), throwsFormatException);
    });

    test('rejects a non-zip payload', () {
      expect(() => EpubParser.parse(utf8.encode('not an epub')), throwsFormatException);
    });

    test('htmlToPlainText keeps paragraph structure and decodes entities', () {
      final text = EpubParser.htmlToPlainText('<p>a</p><p>b &amp; c</p><li>item</li>');
      expect(text.contains('a'), isTrue);
      expect(text.contains('b & c'), isTrue);
      expect(text.contains('• item'), isTrue);
    });
  });

  group('ComicArchive', () {
    List<int> cbz(Map<String, String> entries) => zipOf(entries);

    test('lists image pages in natural order and ignores non-images', () {
      final archive = ComicArchive.open(cbz({
        'comic/page10.jpg': 'x',
        'comic/page2.jpg': 'y',
        'comic/page1.jpg': 'z',
        'comic/readme.txt': 'nope',
        '__MACOSX/._page1.jpg': 'fork',
      }));
      expect(archive.pages, ['comic/page1.jpg', 'comic/page2.jpg', 'comic/page10.jpg']);
      expect(archive.pageBytes(0), isNotEmpty);
    });

    test('skips entries that try to escape the archive root', () {
      final archive = ComicArchive.open(cbz({
        '../../etc/passwd.jpg': 'evil',
        'ok/page1.jpg': 'good',
      }));
      expect(archive.pages, ['ok/page1.jpg']);
    });

    test('isImageFile recognises the supported extensions', () {
      expect(ComicArchive.isImageFile('a/b.PNG'), isTrue);
      expect(ComicArchive.isImageFile('a/b.txt'), isFalse);
      expect(ComicArchive.isImageFile('noextension'), isFalse);
    });

    test('rejects a non-zip payload', () {
      expect(() => ComicArchive.open(utf8.encode('definitely not a zip')), throwsFormatException);
    });
  });
}
