import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Session cache of the videos the app has loaded: a folder in the app's
/// temporary directory, wiped at every start (so it lives exactly as long as
/// the app session, like Instagram). A reel that was loaded once opens from
/// disk the next time (scrolling back, the full-screen viewer, the same reel
/// shared by a friend), with no network wait.
///
/// Files are downloaded whole (reels are a few MB) and named by a hash of
/// the URL. When the cache grows past [maxBytes] the least recently used
/// files are deleted.
class VideoCache {
  /// [directory] pins the folder (tests). Otherwise it is made inside the app's
  /// own temporary directory, which is looked up when the cache is first used:
  /// `Directory.systemTemp` is not writable by an Android app.
  VideoCache({Directory? directory, http.Client? client, this.maxBytes = 300 * 1024 * 1024})
      // ignore: prefer_initializing_formals (a named parameter cannot be private)
      : _directory = directory,
        _client = client ?? http.Client();

  Directory? _directory;
  final int maxBytes;
  final http.Client _client;
  final Map<String, Future<File?>> _inflight = {};

  /// Recency of use per file name (higher = more recent). In memory rather than
  /// file times: the folder only lives one session, and file times can be too
  /// coarse (a second on some systems) to order two videos loaded together.
  final Map<String, int> _used = {};
  int _useCounter = 0;
  static String _nameOf(File file) => file.uri.pathSegments.last; // not the path: separators differ per source
  void _touch(File file) => _used[_nameOf(file)] = ++_useCounter;
  Future<void>? _ready;

  /// Wipes anything left from an earlier session and creates the folder. Runs
  /// once, before the first read or download.
  Future<void> reset() => _ready ??= _reset();

  Future<void> _reset() async {
    try {
      final dir = _directory ??= Directory('${(await getTemporaryDirectory()).path}/forest_video_cache');
      if (dir.existsSync()) await dir.delete(recursive: true);
      await dir.create(recursive: true);
    } on Object catch (e) {
      _directory = null; // nothing is cached without a folder
      debugPrint('Video cache could not be reset: $e');
    }
  }

  /// FNV-1a (64-bit) of the URL, as hex: a short, filesystem-safe file name.
  static String keyFor(String url) {
    var hash = 0xcbf29ce484222325;
    for (final unit in url.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    String half(int v) => (v & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0'); // 64-bit ints are signed: print two masked halves
    return half(hash >> 32) + half(hash);
  }

  static String _extensionOf(String url) {
    final path = Uri.tryParse(url)?.path ?? '';
    final dot = path.lastIndexOf('.');
    final ext = dot < 0 ? '' : path.substring(dot);
    return RegExp(r'^\.[A-Za-z0-9]{2,5}$').hasMatch(ext) ? ext.toLowerCase() : '.mp4';
  }

  File _fileFor(Directory dir, String url) => File('${dir.path}/${keyFor(url)}${_extensionOf(url)}');

  /// The finished file for [url], or null if it is not (completely) cached.
  File? cachedFile(String url) {
    final dir = _directory;
    if (dir == null) return null; // not set up yet
    final file = _fileFor(dir, url);
    if (!file.existsSync()) return null;
    _touch(file); // "recently used"
    return file;
  }

  /// Downloads [url] into the cache unless it is already there (or already on
  /// its way) and returns the file; null when the download failed.
  Future<File?> prefetch(String url) {
    final hit = cachedFile(url);
    if (hit != null) return Future.value(hit);
    // A block body: an arrow returning remove() would hand whenComplete the very
    // future it is building, which would then wait on itself forever.
    return _inflight[url] ??= _download(url).whenComplete(() {
      _inflight.remove(url);
    });
  }

  Future<File?> _download(String url) async {
    await reset();
    final dir = _directory;
    if (dir == null) return null;
    final target = _fileFor(dir, url);
    final part = File('${target.path}.part');
    try {
      // another VideoCache (a second engine after the app was closed and reopened) may have wiped the folder meanwhile
      if (!dir.existsSync()) await dir.create(recursive: true);
      final response = await _client.send(http.Request('GET', Uri.parse(url))).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) return null;
      final sink = part.openWrite();
      try {
        await sink.addStream(response.stream);
      } finally {
        await sink.close();
      }
      await part.rename(target.path); // only whole files ever carry the final name
      _touch(target);
      await _evict(dir);
      return target;
    } on Object catch (e) {
      debugPrint('Video cache download failed for $url: $e');
      try {
        if (part.existsSync()) await part.delete();
      } on Object {
        // ignore
      }
      return null;
    }
  }

  /// Deletes the least recently used files until the cache fits [maxBytes].
  Future<void> _evict(Directory dir) async {
    try {
      final files = [
        for (final e in dir.listSync())
          if (e is File && !e.path.endsWith('.part')) e,
      ]..sort((a, b) => (_used[_nameOf(a)] ?? 0).compareTo(_used[_nameOf(b)] ?? 0));
      var total = files.fold<int>(0, (sum, f) => sum + f.lengthSync());
      for (final f in files) {
        if (total <= maxBytes) break;
        total -= f.lengthSync();
        try {
          f.deleteSync();
          _used.remove(_nameOf(f));
        } on Object {
          // In use on some platforms; it will go next time.
        }
      }
    } on Object catch (e) {
      debugPrint('Video cache eviction failed: $e');
    }
  }
}
