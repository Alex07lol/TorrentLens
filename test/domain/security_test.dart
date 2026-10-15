import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:torrentlens/domain/security/archive_safety.dart';
import 'package:torrentlens/domain/security/integrity.dart';
import 'package:torrentlens/domain/security/url_policy.dart';

void main() {
  group('UrlPolicy', () {
    test('accepts http(s) and rejects dangerous schemes', () {
      expect(UrlPolicy.evaluate('https://example.com/a', use: UrlUse.navigation).isOk, isTrue);
      expect(UrlPolicy.evaluate('javascript:alert(1)', use: UrlUse.navigation).errorOrNull(),
          UrlRejection.schemeNotAllowed);
      expect(UrlPolicy.evaluate('file:///etc/passwd', use: UrlUse.navigation).errorOrNull(),
          UrlRejection.schemeNotAllowed);
      expect(UrlPolicy.evaluate('data:text/html,<b>x</b>', use: UrlUse.navigation).errorOrNull(),
          UrlRejection.schemeNotAllowed);
    });

    test('blocks private hosts for fetches (SSRF protection)', () {
      expect(UrlPolicy.evaluate('http://10.0.0.5/x', use: UrlUse.fetch).errorOrNull(),
          UrlRejection.privateHostBlocked);
      expect(UrlPolicy.evaluate('http://localhost/x', use: UrlUse.fetch).errorOrNull(),
          UrlRejection.privateHostBlocked);
      expect(UrlPolicy.evaluate('http://192.168.1.9/x', use: UrlUse.fetch).errorOrNull(),
          UrlRejection.privateHostBlocked);
      expect(UrlPolicy.evaluate('https://example.com/x', use: UrlUse.fetch).isOk, isTrue);
    });

    test('rejects embedded credentials and relative URLs', () {
      expect(UrlPolicy.evaluate('https://u:p@example.com/', use: UrlUse.fetch).errorOrNull(),
          UrlRejection.credentialsInUrl);
      expect(UrlPolicy.evaluate('/relative/path', use: UrlUse.navigation).isErr, isTrue);
    });

    test('resolves redirects and blocks downgrades/private targets', () {
      final base = Uri.parse('https://example.com/dir/page.html');
      expect(UrlPolicy.resolveRedirect(base, '../a/b.bin').valueOrNull?.toString(),
          'https://example.com/a/b.bin');
      expect(UrlPolicy.resolveRedirect(base, 'http://127.0.0.1/x').isErr, isTrue);
      expect(UrlPolicy.resolveRedirect(base, 'javascript:alert(1)').isErr, isTrue);
    });

    test('sameOrigin ignores path and query', () {
      expect(UrlPolicy.sameOrigin(Uri.parse('https://a.com/x?1'), Uri.parse('https://a.com/y')), isTrue);
      expect(UrlPolicy.sameOrigin(Uri.parse('https://a.com'), Uri.parse('https://b.com')), isFalse);
    });
  });

  group('Integrity', () {
    test('matches published NIST SHA-256 vectors', () {
      expect(Integrity.sha256Hex(utf8.encode('abc')),
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
      expect(Integrity.sha256Hex(const []),
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
    });

    test('accepts a sha256: prefix and is case-insensitive', () {
      final hex = Integrity.sha256Hex(utf8.encode('hello'));
      expect(Integrity.matchesSha256(utf8.encode('hello'), 'sha256:${hex.toUpperCase()}'), isTrue);
      expect(Integrity.matchesSha256(utf8.encode('hello!'), hex), isFalse);
    });

    test('rejects length-mismatched hashes without leaking prefix matches', () {
      expect(Integrity.constantTimeHexEquals('ab', 'abcd'), isFalse);
      expect(Integrity.constantTimeHexEquals('abcd', 'abcd'), isTrue);
    });
  });

  group('ArchiveSafety', () {
    test('normalises safe names', () {
      expect(ArchiveSafety.validateEntryName('a/b/c.txt').valueOrNull, 'a/b/c.txt');
      expect(ArchiveSafety.validateEntryName('./a/../b.bin').valueOrNull, 'b.bin');
    });

    test('rejects traversal, absolute paths, drive letters and backslashes', () {
      expect(ArchiveSafety.validateEntryName('../../etc/passwd').errorOrNull(),
          ArchiveSafetyError.pathTraversal);
      expect(ArchiveSafety.validateEntryName('a/../../b').errorOrNull(),
          ArchiveSafetyError.pathTraversal);
      expect(ArchiveSafety.validateEntryName('/etc/passwd').errorOrNull(),
          ArchiveSafetyError.absolutePath);
      expect(ArchiveSafety.validateEntryName(r'a\b.txt').errorOrNull(),
          ArchiveSafetyError.backslashInName);
      expect(ArchiveSafety.validateEntryName('C:/x').errorOrNull(),
          ArchiveSafetyError.driveLetter);
      expect(ArchiveSafety.validateEntryName('  ').errorOrNull(),
          ArchiveSafetyError.emptyEntryName);
    });

    test('safeJoin keeps everything under the destination', () {
      expect(ArchiveSafety.safeJoin('/data/out', 'img/1.png').valueOrNull, '/data/out/img/1.png');
      expect(ArchiveSafety.safeJoin('/data/out', '../evil').isErr, isTrue);
    });

    test('flags decompression bombs', () {
      expect(ArchiveSafety.checkBudget(entryCount: 10, totalUncompressed: 1000, totalCompressed: 100).isOk, isTrue);
      expect(ArchiveSafety.checkBudget(entryCount: 10, totalUncompressed: (8 << 30) + 1, totalCompressed: 100).errorOrNull(),
          ArchiveSafetyError.totalTooLarge);
      expect(ArchiveSafety.checkBudget(entryCount: 10, totalUncompressed: 100000, totalCompressed: 1).errorOrNull(),
          ArchiveSafetyError.suspiciousCompressionRatio);
    });
  });
}
