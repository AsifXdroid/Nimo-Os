/// LEARN-data — the Library folder (§R6.4) and its write rules.
///
/// One root folder; every database reference to a file inside it
/// is RELATIVE to the root (absolute paths differ phone vs laptop
/// and would break Stage-A sync). Subfolders: `sources/`,
/// `media/`, `packs/`, `html_quizzes/`, `sync/`, `backups/`, and
/// `.nimo/` (library metadata).
///
/// **Write rule (red-team #8, S4 acceptance): every file write is
/// temp-then-rename.** Content lands in `<name>.tmp-<rand>` in the
/// SAME directory, is flushed, then renamed over the target — a
/// sync tool or a crash can never observe a half-written file, and
/// a failed write leaves the previous good file untouched.
///
/// Filenames arriving from outside (share intents, picked files)
/// are UNTRUSTED: [sanitizeFileName] strips any path structure,
/// and [resolve] refuses anything that would escape the root.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/file_names.dart' as file_names;
import '../../core/ids.dart';

class LibraryException implements Exception {
  LibraryException(this.message);
  final String message;
  @override
  String toString() => message;
}

class LibraryStore {
  LibraryStore(this.root);

  /// The Library root. On device: `<app documents>/Library`
  /// (or the owner's override from app_settings — main.dart).
  final Directory root;

  static const List<String> subdirs = [
    'sources',
    'media',
    'packs',
    'html_quizzes',
    'sync',
    'backups',
    '.nimo',
  ];

  /// Files strictly larger than this are refused at import: a
  /// personal library does not need 100 MB+ single files, and the
  /// cap keeps a hostile/accidental share from filling the disk.
  static const int maxImportBytes = 100 * 1024 * 1024;

  String get rootPath => root.path;

  /// Create the §R6.4 layout + `.nimo/library.json` (written
  /// atomically, and only if absent — the file records where the
  /// library was born).
  Future<void> ensureLayout() async {
    for (final sub in subdirs) {
      await Directory(p.join(rootPath, sub)).create(recursive: true);
    }
    final meta = File(p.join(rootPath, '.nimo', 'library.json'));
    if (!await meta.exists()) {
      final json = jsonEncode({
        'library_id': newUuid(),
        'format_version': 1,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
      await writeAtomic('.nimo/library.json', utf8.encode(json));
    }
  }

  /// Resolve a root-relative path to a File, refusing anything
  /// that escapes the root (`..`, absolute paths — lexical check).
  ///
  /// S7 hardening: the Library folder is now also written by an
  /// EXTERNAL sync tool, so a symlink planted inside it (a file
  /// the folder sync delivered, pointing outside) must not turn a
  /// lexical-inside path into an outside read/write. When the
  /// target (or its parent) exists, its canonical path — all
  /// symlinks resolved — must still be within the canonical root.
  File resolve(String relPath) {
    final normalised = p.normalize(relPath);
    if (p.isAbsolute(normalised) ||
        normalised == '..' ||
        normalised.startsWith('..${p.separator}')) {
      throw LibraryException('Path escapes the Library: $relPath');
    }
    final full = p.normalize(p.join(rootPath, normalised));
    if (!p.isWithin(p.normalize(rootPath), full)) {
      throw LibraryException('Path escapes the Library: $relPath');
    }
    _checkNoSymlinkEscape(full, relPath);
    return File(full);
  }

  /// Canonical-path containment check. The nearest EXISTING
  /// ancestor of [full] is canonicalised (all symlinks resolved)
  /// and the not-yet-existing tail re-attached; the result must
  /// stay within the canonical root. (A symlinked directory is
  /// the escape route; a non-existent final component cannot be
  /// a link.)
  void _checkNoSymlinkEscape(String full, String relPath) {
    try {
      var probe = full;
      while (FileSystemEntity.typeSync(probe, followLinks: false) ==
              FileSystemEntityType.notFound &&
          p.dirname(probe) != probe) {
        probe = p.dirname(probe);
      }
      final canonicalRoot =
          Directory(rootPath).resolveSymbolicLinksSync();
      final canonicalProbe = _canonicalise(probe);
      final tail = p.relative(full, from: probe);
      final canonicalFull =
          tail == '.' ? canonicalProbe : p.join(canonicalProbe, tail);
      if (canonicalFull != canonicalRoot &&
          !p.isWithin(canonicalRoot, canonicalFull)) {
        throw LibraryException(
            'Path escapes the Library through a link: $relPath');
      }
    } on LibraryException {
      rethrow;
    } catch (_) {
      // Canonicalisation itself failed (permissions, races): the
      // lexical check above already passed; do not brick the
      // Library over a probe error.
    }
  }

  static String _canonicalise(String path) {
    final type = FileSystemEntity.typeSync(path, followLinks: false);
    if (type == FileSystemEntityType.directory) {
      return Directory(path).resolveSymbolicLinksSync();
    }
    return File(path).resolveSymbolicLinksSync();
  }

  /// The one write path for Library content (red-team #8):
  /// temp file in the target directory → flush → rename. On any
  /// failure the temp file is removed and the previous target (if
  /// any) is left exactly as it was.
  Future<File> writeAtomic(String relPath, List<int> bytes) async {
    final target = resolve(relPath);
    await target.parent.create(recursive: true);
    final tmp = File(
        '${target.path}.tmp-${newUuid().substring(0, 8)}');
    try {
      await tmp.writeAsBytes(bytes, flush: true);
      return await tmp.rename(target.path);
    } catch (_) {
      if (await tmp.exists()) await tmp.delete();
      rethrow;
    }
  }

  /// Copy an external file into [subdir] under a sanitised
  /// version of [originalName]. Name collisions get a short hash
  /// suffix (§R6.4). Returns the root-relative path.
  Future<String> importFile(
    String subdir,
    String sourcePath,
    String originalName,
  ) async {
    final src = File(sourcePath);
    if (!await src.exists()) {
      throw LibraryException('File not found: $sourcePath');
    }
    final length = await src.length();
    if (length > maxImportBytes) {
      throw LibraryException(
          'That file is too large for the Library (limit 100 MB).');
    }
    final bytes = await src.readAsBytes();
    return importBytes(subdir, bytes, originalName);
  }

  /// [importFile] for content already in memory.
  Future<String> importBytes(
    String subdir,
    List<int> bytes,
    String originalName,
  ) async {
    if (bytes.length > maxImportBytes) {
      throw LibraryException(
          'That file is too large for the Library (limit 100 MB).');
    }
    var name = sanitizeFileName(originalName);
    var rel = '$subdir/$name';
    if (await resolve(rel).exists()) {
      final ext = p.extension(name);
      final base = p.basenameWithoutExtension(name);
      name = '$base-${_shortHash(bytes)}$ext';
      rel = '$subdir/$name';
      var n = 2;
      while (await resolve(rel).exists()) {
        name = '$base-${_shortHash(bytes)}-$n$ext';
        rel = '$subdir/$name';
        n++;
      }
    }
    await writeAtomic(rel, bytes);
    return rel;
  }

  Future<List<int>> readBytes(String relPath) =>
      resolve(relPath).readAsBytes();

  Future<String> readText(String relPath) async =>
      utf8.decode(await readBytes(relPath));

  Future<bool> exists(String relPath) => resolve(relPath).exists();

  Future<void> delete(String relPath) async {
    final f = resolve(relPath);
    if (await f.exists()) await f.delete();
  }

  /// Total size + file count of the Library content (the backups
  /// folder is excluded — backups are not content).
  Future<({int files, int bytes})> stats() async {
    var files = 0;
    var bytes = 0;
    if (!await root.exists()) return (files: 0, bytes: 0);
    await for (final entity
        in root.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        final rel = p.relative(entity.path, from: rootPath);
        if (rel.startsWith('backups${p.separator}')) continue;
        files++;
        bytes += await entity.length();
      }
    }
    return (files: files, bytes: bytes);
  }

  /// Make an untrusted external filename safe to store. The rule
  /// itself lives in core (lib/core/file_names.dart) — this is a
  /// forwarder so Library call sites read naturally.
  static String sanitizeFileName(String name) =>
      file_names.sanitizeFileName(name);

  /// FNV-1a over the content, 6 hex chars — collision suffixes
  /// only need to be short and stable, not cryptographic.
  static String _shortHash(List<int> bytes) {
    var hash = 0x811c9dc5;
    for (final b in bytes) {
      hash ^= b;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0').substring(0, 6);
  }
}
