/// AUDIO item (D-054) — an audio file in the Library,
/// played in place from the item detail. It is the resource
/// behind listening tasks: a plan task links to an audio
/// item and its row action ("Listen →") opens this screen.
///
/// Mirrors the HTML item's shape: the file is COPIED into
/// the Library (`audio/`), the item payload carries only
/// `file_rel_path`, and playback happens here — v1 is
/// foreground playback in this screen (play/pause + seek);
/// background/notification playback is out of scope.
library;

import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;

import '../../learn/library_store.dart';
import '../../store.dart';

/// Picker filter for audio imports.
const audioFileGroup = XTypeGroup(
  label: 'Audio files',
  extensions: ['mp3', 'm4a', 'aac', 'wav', 'ogg', 'opus', 'flac'],
);

/// The display file name for an audio item's payload.
String audioFileName(Map<String, Object?>? payload) {
  final rel = payload?['file_rel_path'];
  if (rel is String && rel.isNotEmpty) return p.basename(rel);
  return '';
}

/// Import [sourcePath] into the Library's `audio/` folder
/// and create the item in [projectId]. Title = the file's
/// base name (the owner can rename it like any item).
Future<Item> importAudioItem({
  required Store store,
  required LibraryStore library,
  required int projectId,
  required String sourcePath,
  required String sourceName,
}) async {
  final rel = await library.importFile('audio', sourcePath, sourceName);
  final base = p.basenameWithoutExtension(sourceName);
  try {
    return await store.createItem(
      projectId,
      type: ItemType.audio,
      title: base.isEmpty ? sourceName : base,
      payload: {'file_rel_path': rel},
    );
  } catch (_) {
    // The copy landed but the row did not (Phase 8 review,
    // defect A): remove the just-imported file so a failed
    // import leaves no orphan. importBytes always writes a
    // NEW, uniquely-named file, so nothing else can
    // reference this path yet. Cleanup failure stays silent
    // — the original error is the one that matters.
    try {
      final file = library.resolve(rel);
      if (await file.exists()) await file.delete();
    } catch (_) {}
    rethrow;
  }
}

/// Relink [item] to a NEW audio file (Phase 8): the file is
/// copied into the Library through the same import path as a
/// fresh import, and the payload is updated ONLY after the
/// copy exists — a failed copy leaves the item exactly as it
/// was. The old file is deliberately NOT deleted here: it may
/// be shared, and cleanup belongs to the guarded delete path.
Future<bool> relinkAudioItem({
  required Store store,
  required LibraryStore library,
  required Item item,
  required String sourcePath,
  required String sourceName,
}) async {
  final String rel;
  try {
    rel = await library.importFile('audio', sourcePath, sourceName);
  } catch (_) {
    return false;
  }
  await store.updateItemPayloadField(item.id, 'file_rel_path', rel);
  await store.updateItemPayloadField(item.id, 'position_ms', 0);
  return true;
}

/// The saved resume position for an audio item, in
/// milliseconds (0 when absent — older payloads stay valid).
int audioSavedPositionMs(Map<String, Object?>? payload) {
  final v = payload?['position_ms'];
  return v is num && v > 0 ? v.toInt() : 0;
}

class AudioItemBody extends StatefulWidget {
  const AudioItemBody({
    super.key,
    required this.item,
    required this.library,
    required this.store,
    this.onRemoveItem,
  });

  final Item item;
  final LibraryStore? library;

  /// The store (Phase 8): resume persistence + relink write
  /// through the same instance the detail screen uses.
  final Store store;

  /// Remove-this-item action for the missing-file state
  /// (Phase 8): the detail screen supplies it (it owns the
  /// confirm + pop); null hides the action.
  final Future<void> Function()? onRemoveItem;

  @override
  State<AudioItemBody> createState() => _AudioItemBodyState();
}

class _AudioItemBodyState extends State<AudioItemBody> {
  /// Created lazily in [_load], only once the file is known
  /// to exist — a missing file never spins up a player.
  /// The live item: starts as the widget's item; a relink
  /// replaces it with the freshly-read row (new payload).
  late Item _item;

  AudioPlayer? _player;
  bool _loading = true;
  String? _error;
  bool _missingFile = false;

  // Resume-position persistence (Phase 8): ONE serialised
  // write chain per body instance. Position events only update
  // [_latestPositionMs] and schedule a throttled flush; seek,
  // pause and dispose flush immediately; completion bumps the
  // generation so every queued write is invalidated and the
  // reset to zero is authoritative. An older write can never
  // land after a newer one.
  Future<void> _writeChain = Future<void>.value();
  int _latestPositionMs = 0;
  int _generation = 0;
  bool _completed = false;
  Timer? _flushTimer;
  bool _seekedToSaved = false;

  @override
  void initState() {
    super.initState();
    _item = widget.item;
    _load();
  }

  Future<void> _load() async {
    final library = widget.library;
    final payload = _item.payload ?? const <String, Object?>{};
    final rel = payload['file_rel_path'];
    if (library == null || rel is! String || rel.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'Library is not available.';
      });
      return;
    }
    final File file;
    try {
      file = library.resolve(rel);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _missingFile = true;
        _error = missingAudioMessage;
      });
      return;
    }
    if (!await file.exists()) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _missingFile = true;
        _error = missingAudioMessage;
      });
      return;
    }
    _player = AudioPlayer();
    try {
      await _player!.setFilePath(file.path);
      final saved = audioSavedPositionMs(_item.payload);
      if (saved > 0 && !_seekedToSaved) {
        _seekedToSaved = true;
        _latestPositionMs = saved;
        await _player!.seek(Duration(milliseconds: saved));
      }
      _player!.positionStream.listen(_onPosition);
      _player!.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          _onCompleted();
        }
      });
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not play this file.';
      });
    }
  }

  /// The honest missing-file copy (Phase 8): the entry is
  /// safe; the FILE is not in this device's Library. Files
  /// travel with a full backup or a Library folder sync —
  /// the light sync moves entries only.
  static const String missingAudioMessage =
      'The audio file is not in this device\'s Library. '
      'Audio files travel with a full backup or a Library '
      'folder sync — the light sync moves entries only. '
      'Find the file to keep listening.';

  void _onPosition(Duration position) {
    if (_completed) return;
    _latestPositionMs = position.inMilliseconds;
    _flushTimer ??= Timer(const Duration(seconds: 5), () {
      _flushTimer = null;
      _flushPosition();
    });
  }

  /// Queue a merge-write of the latest position behind every
  /// earlier write. [generation] pins the write to this
  /// playback session: completion (or a newer session) makes
  /// stale writes no-ops.
  void _flushPosition() {
    final gen = _generation;
    final value = _latestPositionMs;
    _writeChain = _writeChain.then((_) async {
      if (gen != _generation || _completed) return;
      try {
        await _store.updateItemPayloadField(
          _item.id,
          'position_ms',
          value,
        );
      } catch (_) {
        // A failed position save loses the resume point,
        // never the item.
      }
    });
  }

  void _onCompleted() {
    if (_completed) return;
    _completed = true;
    _generation++;
    _latestPositionMs = 0;
    _flushTimer?.cancel();
    _flushTimer = null;
    _writeChain = _writeChain.then((_) async {
      try {
        await _store.updateItemPayloadField(
          _item.id,
          'position_ms',
          0,
        );
      } catch (_) {}
    });
  }

  Store get _store => widget.store;

  Future<void> _findFile() async {
    final library = widget.library;
    if (library == null) return;
    final picked = await openFile(acceptedTypeGroups: const [audioFileGroup]);
    if (picked == null || !mounted) return;
    final ok = await relinkAudioItem(
      store: widget.store,
      library: library,
      item: _item,
      sourcePath: picked.path,
      sourceName: picked.name,
    );
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not copy that file.')),
      );
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _missingFile = false;
      _completed = false;
      _seekedToSaved = false;
    });
    await _player?.dispose();
    _player = null;
    // Reload against the updated payload.
    final fresh = await widget.store.itemById(_item.id);
    if (!mounted) return;
    _item = fresh;
    _load();
  }

  @override
  void dispose() {
    _flushTimer?.cancel();
    _flushTimer = null;
    if (!_completed && _player != null) _flushPosition();
    _player?.dispose();
    super.dispose();
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final payload = _item.payload ?? const <String, Object?>{};
    final fileName = audioFileName(payload);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.3,
          ),
          child: Row(
            children: [
              const Icon(Icons.headphones_outlined, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  fileName.isNotEmpty ? fileName : _item.title,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _error!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        if (_missingFile) ...[
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: _findFile,
                            child: const Text('Find the file'),
                          ),
                          if (widget.onRemoveItem != null)
                            TextButton(
                              onPressed: widget.onRemoveItem,
                              child: const Text('Remove this item'),
                            ),
                        ],
                      ],
                    ),
                  ),
                )
              : _loading
              ? const Center(child: CircularProgressIndicator())
              : _controls(context),
        ),
      ],
    );
  }

  Widget _controls(BuildContext context) {
    final theme = Theme.of(context);
    // Only built after a successful load, so the player exists.
    final player = _player!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          StreamBuilder<PlayerState>(
            stream: player.playerStateStream,
            builder: (context, snapshot) {
              final state = snapshot.data;
              final playing = state?.playing ?? false;
              final completed =
                  state?.processingState == ProcessingState.completed;
              return IconButton.filled(
                iconSize: 56,
                onPressed: () async {
                  if (completed) {
                    _completed = false;
                    _generation++;
                    await player.seek(Duration.zero);
                    _latestPositionMs = 0;
                    _flushPosition();
                    player.play();
                  } else if (playing) {
                    await player.pause();
                    _latestPositionMs = player.position.inMilliseconds;
                    _flushPosition();
                  } else {
                    player.play();
                  }
                },
                icon: Icon(
                  completed
                      ? Icons.replay
                      : playing
                      ? Icons.pause
                      : Icons.play_arrow,
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          StreamBuilder<Duration>(
            stream: player.positionStream,
            builder: (context, snapshot) {
              final position = snapshot.data ?? Duration.zero;
              final duration = player.duration ?? Duration.zero;
              final max = duration.inMilliseconds.toDouble();
              final value = max <= 0
                  ? 0.0
                  : position.inMilliseconds.clamp(0, max).toDouble();
              return Column(
                children: [
                  Slider(
                    value: value,
                    max: max <= 0 ? 1 : max,
                    onChanged: max <= 0
                        ? null
                        : (v) {
                            final ms = v.round();
                            _latestPositionMs = ms;
                            player.seek(Duration(milliseconds: ms));
                            _flushPosition();
                          },
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_fmt(position), style: theme.textTheme.bodySmall),
                      Text(_fmt(duration), style: theme.textTheme.bodySmall),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
