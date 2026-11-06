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
  return store.createItem(
    projectId,
    type: ItemType.audio,
    title: base.isEmpty ? sourceName : base,
    payload: {'file_rel_path': rel},
  );
}

class AudioItemBody extends StatefulWidget {
  const AudioItemBody({super.key, required this.item, required this.library});

  final Item item;
  final LibraryStore? library;

  @override
  State<AudioItemBody> createState() => _AudioItemBodyState();
}

class _AudioItemBodyState extends State<AudioItemBody> {
  /// Created lazily in [_load], only once the file is known
  /// to exist — a missing file never spins up a player.
  AudioPlayer? _player;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final library = widget.library;
    final payload = widget.item.payload ?? const <String, Object?>{};
    final rel = payload['file_rel_path'];
    if (library == null || rel is! String || rel.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'Library is not available.';
      });
      return;
    }
    final file = library.resolve(rel);
    if (!await file.exists()) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'The audio file is missing from the Library.';
      });
      return;
    }
    _player = AudioPlayer();
    try {
      await _player!.setFilePath(file.path);
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

  @override
  void dispose() {
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
    final payload = widget.item.payload ?? const <String, Object?>{};
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
                  fileName.isNotEmpty ? fileName : widget.item.title,
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
                    child: Text(
                      _error!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
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
                    await player.seek(Duration.zero);
                    player.play();
                  } else if (playing) {
                    await player.pause();
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
                        : (v) => player.seek(Duration(milliseconds: v.round())),
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
