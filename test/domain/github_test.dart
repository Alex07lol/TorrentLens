import 'package:flutter_test/flutter_test.dart';
import 'package:torrentlens/domain/github/github_ref.dart';
import 'package:torrentlens/domain/github/semantic_version.dart';

void main() {
  group('GitHubRef', () {
    test('parses repo, releases, tag and latest URLs', () {
      expect(GitHubRef.tryParse('https://github.com/owner/repo')!.fullName, 'owner/repo');
      expect(GitHubRef.tryParse('https://github.com/owner/repo.git')!.fullName, 'owner/repo');
      final tag = GitHubRef.tryParse('https://github.com/owner/repo/releases/tag/v1.2.3')!;
      expect(tag.isRelease, isTrue);
      expect(tag.tag, 'v1.2.3');
      expect(GitHubRef.tryParse('https://github.com/owner/repo/releases/latest')!.tag, 'latest');
    });

    test('parses bare owner/repo shorthand', () {
      expect(GitHubRef.tryParse('owner/repo')!.repo, 'repo');
    });

    test('rejects reserved owners and other hosts', () {
      expect(GitHubRef.tryParse('https://github.com/settings/repo'), isNull);
      expect(GitHubRef.tryParse('https://gitlab.com/owner/repo'), isNull);
      expect(GitHubRef.tryParse('https://github.com/owner'), isNull);
    });
  });

  group('SemanticVersion', () {
    test('orders by major/minor/patch', () {
      expect(SemanticVersion.tryParse('1.2.3')! < SemanticVersion.tryParse('1.10.0')!, isTrue);
      expect(SemanticVersion.tryParse('2.0.0')! > SemanticVersion.tryParse('1.9.9')!, isTrue);
    });

    test('prerelease has lower precedence than release', () {
      expect(SemanticVersion.tryParse('1.0.0-rc.1')! < SemanticVersion.tryParse('1.0.0')!, isTrue);
      expect(SemanticVersion.tryParse('1.0.0-alpha')! < SemanticVersion.tryParse('1.0.0-beta')!, isTrue);
      expect(SemanticVersion.tryParse('1.0.0-rc.1')! < SemanticVersion.tryParse('1.0.0-rc.2')!, isTrue);
      expect(SemanticVersion.tryParse('1.0.0-2')! < SemanticVersion.tryParse('1.0.0-11')!, isTrue);
    });

    test('tolerates a leading v and build metadata', () {
      expect(SemanticVersion.tryParse('v1.2.3+meta')!.toString(), '1.2.3+meta');
    });

    test('rejects malformed input', () {
      expect(SemanticVersion.tryParse('1.2'), isNull);
      expect(SemanticVersion.tryParse('latest'), isNull);
    });
  });
}
