import 'dart:io';
import 'dart:typed_data';

import '../../app/services.dart';
import '../../domain/models/torrent_task.dart';
import '../../domain/torrent/magnet_uri.dart';
import '../../domain/torrent/task_state.dart';
import '../../domain/torrent/torrent_source.dart';
import '../../integrations/torrent/torrent_engine.dart';
import '../../util/format.dart';
import 'torrent_fetch.dart';

class ImportResult {
  final bool ok;
  final String? infoHash;
  final String? taskId;
  final String? error;
  final TorrentMetadata? metadata;
  const ImportResult({required this.ok, this.infoHash, this.taskId, this.error, this.metadata});
}

/// Owns the "add a torrent" workflow: validate the input, start the engine,
/// resolve metadata, persist a task + its (sanitized) file list.
///
/// It never fabricates progress: the task is created in `resolvingMetadata` and
/// only moves on when the engine reports a real state.
class TorrentImportService {
  final AppServices services;
  TorrentImportService(this.services);

  Future<ImportResult> addMagnet(String raw, {String? savePath}) async {
    final magnet = MagnetUri.tryParse(raw);
    if (magnet == null) {
      // Distinguish the failure reasons so the UI can be specific.
      try {
        MagnetUri.parse(raw);
      } on MagnetUriParseException catch (e) {
        return ImportResult(ok: false, error: _magnetError(e.error));
      }
      return const ImportResult(ok: false, error: 'That is not a valid magnet link.');
    }
    return _addMagnet(magnet, savePath ?? await _defaultDir());
  }

  Future<ImportResult> addTorrentBytes(Uint8List bytes, {String? savePath, String? name}) async {
    if (bytes.isEmpty) {
      return const ImportResult(ok: false, error: 'That .torrent file is empty.');
    }
    final dir = savePath ?? await _defaultDir();
    try {
      await _ensureEngine();
      final infoHash = await services.engine.addTorrentFile(bytes, dir);
      return await _persistAndResolve(infoHash, name ?? 'Torrent', dir, TorrentSourceKind.torrentFile);
    } on TorrentEngineException catch (e) {
      return ImportResult(ok: false, error: e.message);
    } catch (e) {
      return ImportResult(ok: false, error: '$e');
    }
  }

  /// Downloads a `.torrent` over HTTP(S) and imports the **original bytes**.
  ///
  /// The previous implementation went through `response.body` (a UTF-8 decode)
  /// and re-encoded it with `codeUnits`, which corrupts every torrent whose
  /// bytes fall outside ASCII. [TorrentFileFetcher] never decodes the body, and
  /// validates the destination directory before anything is added.
  Future<ImportResult> addTorrentUrl(String url, {String? savePath}) async {
    final validated = TorrentSource.classify(url);
    if (validated.kind != TorrentSourceKind.torrentUrl) {
      return const ImportResult(
          ok: false, error: 'Only http(s) URLs ending in .torrent are supported here.');
    }
    final dir = savePath ?? await _defaultDir();
    final dirProblem = await _checkDir(dir);
    if (dirProblem != null) return ImportResult(ok: false, error: dirProblem);

    final fetched = await TorrentFileFetcher(services.fetcher).fetch(url);
    final bytes = fetched.bytes;
    if (bytes == null) {
      return ImportResult(ok: false, error: fetched.message ?? 'Could not download that .torrent file.');
    }
    final name = fetched.finalUrl?.pathSegments.isNotEmpty == true
        ? fetched.finalUrl!.pathSegments.last
        : Uri.parse(url).pathSegments.last;
    return addTorrentBytes(bytes, savePath: dir, name: name);
  }

  /// The engine writes into [dir]; make sure it exists and is writable before a
  /// torrent is added, so a bad path fails here with a clear message instead of
  /// leaving a task that can never download.
  Future<String?> _checkDir(String dir) async {
    if (dir.trim().isEmpty) return 'No download folder is configured.';
    final target = Directory(dir);
    try {
      if (!await target.exists()) await target.create(recursive: true);
    } catch (e) {
      return 'Cannot create the download folder "$dir": $e';
    }
    return null;
  }

  Future<ImportResult> _addMagnet(MagnetUri magnet, String dir) async {
    try {
      await _ensureEngine();
      final infoHash = await services.engine.addMagnet(magnet.raw, dir);
      return await _persistAndResolve(
          infoHash, magnet.displayName ?? 'Magnet ${infoHash.substring(0, 8)}', dir, TorrentSourceKind.magnet);
    } on TorrentEngineException catch (e) {
      return ImportResult(ok: false, error: e.message, infoHash: magnet.infoHash.toHex());
    } catch (e) {
      return ImportResult(ok: false, error: '$e');
    }
  }

  Future<ImportResult> _persistAndResolve(
      String infoHash, String name, String dir, TorrentSourceKind kind) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final task = TorrentTask(
      id: Ids.newId('task'),
      infoHashHex: infoHash,
      name: name,
      state: TorrentTaskState.resolvingMetadata,
      savePath: dir,
      totalBytes: 0,
      downloadedBytes: 0,
      downloadBps: 0,
      uploadBps: 0,
      connectedPeers: 0,
      addedAtMs: now,
      updatedAtMs: now,
      sourceKind: kind.name,
    );
    await services.torrents.upsertTask(task);

    TorrentMetadata? metadata;
    try {
      metadata = await services.engine.metadata(infoHash);
      if (metadata.files.isNotEmpty) {
        await services.torrents.replaceFiles(
          task.id,
          [
            for (final f in metadata.files)
              TorrentFileEntry(taskId: task.id, fileIndex: f.index, path: f.path, sizeBytes: f.sizeBytes),
          ],
        );
        await services.torrents.upsertTask(task.copyWith(
          totalBytes: metadata.totalBytes,
          name: name,
          state: TorrentTaskState.downloading,
          updatedAtMs: DateTime.now().millisecondsSinceEpoch,
        ));
      }
    } catch (_) {
      // Metadata may legitimately still be pending; the poller will pick it up.
    }

    return ImportResult(ok: true, infoHash: infoHash, taskId: task.id, metadata: metadata);
  }

  Future<void> _ensureEngine() async {
    if (!await services.engine.isRunning()) {
      await services.engine.start(const EngineOptions());
    }
  }

  Future<String> _defaultDir() async {
    final saved = await services.settings.get('storage.downloadDir');
    return saved ?? services.defaultDownloadDir;
  }

  String _magnetError(MagnetParseError e) => switch (e) {
        MagnetParseError.notAMagnet => 'That is not a magnet link.',
        MagnetParseError.missingInfoHash => 'The magnet link has no info-hash (xt=urn:btih:).',
        MagnetParseError.unsupportedHash =>
          'BitTorrent v2 (btmh) magnets are not supported by the selected engine.',
        MagnetParseError.invalidInfoHash => 'The info-hash in that magnet link is malformed.',
        MagnetParseError.duplicateInfoHash => 'The magnet link contains two different info-hashes.',
      };
}
