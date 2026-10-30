/// LEARN-data — share-intent capture (§R8.2, §R9.5).
///
/// Friction is the enemy (§R9.5): a share lands as ONE pre-filled
/// confirm sheet — title guessed from the share, Save = 1 tap —
/// and becomes a topic in the Inbox project. Organising is
/// deferred to triage, never asked at capture time.
///
/// The platform side sits behind [ShareIntentService] so the
/// whole flow is testable with a fake: tests never touch a
/// platform channel. Since D-034 the platform side is in-house —
/// MainActivity decodes ACTION_SEND intents and serves them over
/// the `app.dailylife/share_intent` channels (the
/// receive_sharing_intent plugin is defective in every published
/// version under this project's toolchain; see
/// docs/CI_BUILD_AUDIT-2026-10-30.md).
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'import_service.dart';
import 'learn_store.dart';

/// What kind of thing was shared.
enum CaptureKind { link, text, file }

/// One incoming share, normalised away from the plugin's types.
class SharedCapture {
  const SharedCapture({
    required this.kind,
    this.text,
    this.filePath,
    this.fileName,
  });

  final CaptureKind kind;

  /// The URL (link) or the shared text (text).
  final String? text;

  /// Local path of a shared file (the platform side copies shares
  /// into the app cache — capture copies it into the Library
  /// promptly).
  final String? filePath;

  /// Display name of a shared file (UNTRUSTED — the Library
  /// sanitises it again at import).
  final String? fileName;

  /// The pre-filled title for the confirm sheet.
  String get suggestedTitle {
    switch (kind) {
      case CaptureKind.link:
        final url = text ?? '';
        final uri = Uri.tryParse(url);
        final host = uri?.host ?? '';
        return host.isNotEmpty ? 'Link from $host' : 'Shared link';
      case CaptureKind.text:
        final firstLine = (text ?? '')
            .split('\n')
            .map((l) => l.trim())
            .firstWhere((l) => l.isNotEmpty, orElse: () => 'Shared text');
        return firstLine.length > 60
            ? '${firstLine.substring(0, 60)}…'
            : firstLine;
      case CaptureKind.file:
        return fileName ?? 'Shared file';
    }
  }
}

/// The boundary the UI talks to. The in-house implementation is
/// [AppShareIntentService]; tests use a fake.
abstract interface class ShareIntentService {
  /// The share that launched the app (cold start), if any.
  Future<List<SharedCapture>> initialCaptures();

  /// Shares arriving while the app runs (warm intents).
  Stream<SharedCapture> get captures;

  /// Tell the platform the pending share was consumed.
  Future<void> markConsumed();
}

/// In-house implementation (D-034): MainActivity decodes Android
/// ACTION_SEND / ACTION_SEND_MULTIPLE intents into
/// `{kind: text|file, value}` payloads — text stays text (a bare
/// URL is upgraded to a link here, exactly as the plugin-era
/// conversion did), files arrive as private cache copies whose
/// paths the Library imports from promptly. The plugin's video
/// thumbnail/duration extras were never used and are not
/// reproduced.
class AppShareIntentService implements ShareIntentService {
  static const MethodChannel _methods =
      MethodChannel('app.dailylife/share_intent');
  static const EventChannel _events =
      EventChannel('app.dailylife/share_intent/events');

  @override
  Future<List<SharedCapture>> initialCaptures() async {
    try {
      final raw =
          await _methods.invokeListMethod<Object?>('getInitialMedia');
      return (raw ?? const [])
          .map(_convert)
          .whereType<SharedCapture>()
          .toList();
    } catch (_) {
      // No platform (desktop/tests without the channel): no share.
      return const [];
    }
  }

  @override
  Stream<SharedCapture> get captures => _events
      .receiveBroadcastStream()
      .expand((event) => (event as List)
          .map(_convert)
          .whereType<SharedCapture>());

  @override
  Future<void> markConsumed() => _methods.invokeMethod<void>('reset');

  static SharedCapture? _convert(Object? item) {
    if (item is! Map) return null;
    final value = item['value'];
    if (value is! String) return null;
    switch (item['kind']) {
      case 'text':
        // Some apps share URLs AS text: a bare URL is a link.
        final text = value.trim();
        final uri = Uri.tryParse(text);
        if (uri != null &&
            (uri.scheme == 'http' || uri.scheme == 'https') &&
            !text.contains(RegExp(r'\s'))) {
          return SharedCapture(kind: CaptureKind.link, text: text);
        }
        return SharedCapture(kind: CaptureKind.text, text: value);
      case 'file':
        final name = value.split(RegExp(r'[/\\]')).last;
        return SharedCapture(
          kind: CaptureKind.file,
          filePath: value,
          fileName: name,
        );
      default:
        return null;
    }
  }
}

/// Saves a confirmed capture into the Inbox: a topic, plus its
/// first source (the link itself, or the imported file).
/// A capture that could not be saved at all (e.g. the shared
/// file vanished before confirmation). Surfaced to the owner —
/// never converted into a silent empty topic.
class CaptureException implements Exception {
  CaptureException(this.message);
  final String message;
  @override
  String toString() => message;
}

class CaptureService {
  CaptureService(this._learn, this._imports);

  final LearnStore _learn;
  final ImportService _imports;

  /// [title] is the confirm sheet's (owner-editable) title.
  Future<Topic> saveCapture(SharedCapture capture, {String? title}) async {
    final inboxId = await _learn.inboxProjectId();
    final topicTitle = (title == null || title.trim().isEmpty)
        ? capture.suggestedTitle
        : title.trim();
    switch (capture.kind) {
      case CaptureKind.link:
        final topic = await _learn.createTopic(
          projectId: inboxId,
          title: topicTitle,
          triggerUrl: capture.text,
        );
        await _imports.importLink(
            topicId: topic.id, url: capture.text ?? '', title: topicTitle);
        return topic;
      case CaptureKind.text:
        final topic = await _learn.createTopic(
          projectId: inboxId,
          title: topicTitle,
        );
        await _imports.importTextContent(
          topicId: topic.id,
          text: capture.text ?? '',
          title: topicTitle,
        );
        return topic;
      case CaptureKind.file:
        // The platform side hands us a cache path that Android may
        // clean before the owner confirms. A vanished file is a
        // FAILED capture — never an empty topic wearing a success
        // message (§R9.5: capture must not lose things silently).
        final path = capture.filePath;
        if (path == null || !await File(path).exists()) {
          throw CaptureException(
              'The shared file is no longer available on this device.');
        }
        final topic = await _learn.createTopic(
          projectId: inboxId,
          title: topicTitle,
        );
        try {
          await _imports.importFile(
            topicId: topic.id,
            sourcePath: path,
            originalName: capture.fileName ?? 'shared-file',
            title: topicTitle,
          );
        } catch (_) {
          // Keep failure atomic from the owner's side: no empty
          // topic left behind by a refused import (e.g. oversize).
          await _learn.deleteTopic(topic.id);
          rethrow;
        }
        return topic;
    }
  }
}
