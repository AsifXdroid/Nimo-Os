/// LEARN-data — share-intent capture (§R8.2, §R9.5).
///
/// Friction is the enemy (§R9.5): a share lands as ONE pre-filled
/// confirm sheet — title guessed from the share, Save = 1 tap —
/// and becomes a topic in the Inbox project. Organising is
/// deferred to triage, never asked at capture time.
///
/// The platform plugin (`receive_sharing_intent`) sits behind
/// [ShareIntentService] so the whole flow is testable with a fake:
/// tests never touch a platform channel.
library;

import 'dart:async';
import 'dart:io';

import 'package:receive_sharing_intent/receive_sharing_intent.dart';

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

  /// Local path of a shared file (the plugin copies shares into a
  /// temp cache — capture copies it into the Library promptly).
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

/// The boundary the UI talks to. The plugin implementation is
/// [PluginShareIntentService]; tests use a fake.
abstract interface class ShareIntentService {
  /// The share that launched the app (cold start), if any.
  Future<List<SharedCapture>> initialCaptures();

  /// Shares arriving while the app runs (warm intents).
  Stream<SharedCapture> get captures;

  /// Tell the platform the pending share was consumed.
  Future<void> markConsumed();
}

/// `receive_sharing_intent` implementation (Android ACTION_SEND).
class PluginShareIntentService implements ShareIntentService {
  @override
  Future<List<SharedCapture>> initialCaptures() async {
    try {
      final media = await ReceiveSharingIntent.instance.getInitialMedia();
      return media.map(_convert).whereType<SharedCapture>().toList();
    } catch (_) {
      // No platform (desktop/tests without the plugin): no share.
      return const [];
    }
  }

  @override
  Stream<SharedCapture> get captures => ReceiveSharingIntent.instance
      .getMediaStream()
      .expand((list) => list.map(_convert).whereType<SharedCapture>());

  @override
  Future<void> markConsumed() => ReceiveSharingIntent.instance.reset();

  static SharedCapture? _convert(SharedMediaFile media) {
    switch (media.type) {
      case SharedMediaType.url:
        return SharedCapture(kind: CaptureKind.link, text: media.path);
      case SharedMediaType.text:
        // Some apps share URLs AS text: a bare URL is a link.
        final text = media.path.trim();
        final uri = Uri.tryParse(text);
        if (uri != null &&
            (uri.scheme == 'http' || uri.scheme == 'https') &&
            !text.contains(RegExp(r'\s'))) {
          return SharedCapture(kind: CaptureKind.link, text: text);
        }
        return SharedCapture(kind: CaptureKind.text, text: media.path);
      case SharedMediaType.file:
      case SharedMediaType.image:
      case SharedMediaType.video:
        final name = media.path.split(RegExp(r'[/\\]')).last;
        return SharedCapture(
          kind: CaptureKind.file,
          filePath: media.path,
          fileName: name,
        );
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
        // The plugin hands us a temp-cache path that Android may
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
