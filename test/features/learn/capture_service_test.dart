// LEARN-data — share-intent capture (S4, §R8.2/§R9.5): the
// platform side sits behind ShareIntentService; its conversion
// is tested through the in-house channel contract (D-034 — mock
// binary-messenger handlers stand in for MainActivity), and the
// save path through CaptureService with a hand-written fake —
// cold start and warm stream both land as Inbox topics in ≤ the
// one confirm tap.
import 'dart:async';
import 'dart:io';

import 'package:daily_life_app/core/db/app_database.dart';
import 'package:daily_life_app/features/learn/capture_service.dart';
import 'package:daily_life_app/features/learn/import_service.dart';
import 'package:daily_life_app/features/learn/learn_store.dart';
import 'package:daily_life_app/features/learn/library_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class FakeShareIntentService implements ShareIntentService {
  FakeShareIntentService(this.initial, this.stream);
  final List<SharedCapture> initial;
  final Stream<SharedCapture> stream;
  bool consumed = false;

  @override
  Future<List<SharedCapture>> initialCaptures() async => initial;

  @override
  Stream<SharedCapture> get captures => stream;

  @override
  Future<void> markConsumed() async {
    consumed = true;
  }
}

void main() {
  setUpAll(() {
    // For the channel mocks (TestDefaultBinaryMessengerBinding).
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tmp;
  late LearnStore learn;
  late LibraryStore library;
  late CaptureService capture;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('nimo-capture-');
    final db = await AppDatabase.openInMemory();
    // The ffi in-memory DB is shared per process — start clean.
    for (final t in [
      'sources',
      'topics',
      'items',
      'projects',
      'workspaces',
      'app_settings',
    ]) {
      await db.delete(t);
    }
    learn = LearnStore(db);
    library = LibraryStore(Directory('${tmp.path}/Library'));
    await library.ensureLayout();
    capture = CaptureService(
        learn, ImportService(learn, library, pdfExtractor: (_) async => ['x']));
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  group('channel conversion (MainActivity contract, D-034)', () {
    const methodChannel = MethodChannel('app.dailylife/share_intent');
    const eventChannel =
        EventChannel('app.dailylife/share_intent/events');

    late List<Object?> mockInitial;
    late List<Object?> mockEvents;

    setUp(() {
      mockInitial = const [];
      mockEvents = const [];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(methodChannel, (call) async {
        switch (call.method) {
          case 'getInitialMedia':
            return mockInitial;
          case 'reset':
            return null;
          default:
            return null;
        }
      });
      messenger.setMockStreamHandler(
        eventChannel,
        MockStreamHandler.inline(
          onListen: (args, events) {
            for (final e in mockEvents) {
              events.success(e);
            }
            events.endOfStream();
          },
        ),
      );
    });

    tearDown(() {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(methodChannel, null);
      messenger.setMockStreamHandler(eventChannel, null);
    });

    test('cold-start URL share becomes a link capture', () async {
      mockInitial = [
        {'kind': 'text', 'value': 'https://instagram.com/reel/abc'},
      ];
      final captures = await AppShareIntentService().initialCaptures();
      expect(captures.single.kind, CaptureKind.link);
      expect(captures.single.text, 'https://instagram.com/reel/abc');
      expect(captures.single.suggestedTitle, 'Link from instagram.com');
    });

    test('a bare URL shared AS text is still a link', () async {
      mockInitial = [
        {'kind': 'text', 'value': 'https://example.com/article'},
      ];
      final captures = await AppShareIntentService().initialCaptures();
      expect(captures.single.kind, CaptureKind.link);
    });

    test('warm stream: text stays text, files carry their name',
        () async {
      mockEvents = [
        [
          {'kind': 'text', 'value': 'Some thought worth keeping'},
        ],
        [
          {'kind': 'file', 'value': '/cache/shared/notes.txt'},
        ],
      ];
      final got = await AppShareIntentService().captures.toList();
      expect(got.map((c) => c.kind), [CaptureKind.text, CaptureKind.file]);
      expect(got.last.fileName, 'notes.txt');
    });
  });

  group('saveCapture → Inbox topic', () {
    test('a file capture whose file has vanished fails loudly and '
        'creates nothing (no empty topic, no fake save)', () async {
      final before = (await learn.allTopics()).length;
      await expectLater(
        capture.saveCapture(const SharedCapture(
          kind: CaptureKind.file,
          filePath: '/nonexistent/cleaned-by-android.pdf',
          fileName: 'cleaned-by-android.pdf',
        )),
        throwsA(isA<CaptureException>()),
      );
      expect((await learn.allTopics()).length, before);
    });

    test('link capture: topic + trigger + link source', () async {
      final topic = await capture.saveCapture(const SharedCapture(
        kind: CaptureKind.link,
        text: 'https://instagram.com/reel/abc',
      ));
      final inboxId = await learn.inboxProjectId();
      expect(topic.projectId, inboxId);
      expect(topic.triggerUrl, 'https://instagram.com/reel/abc');
      final sources = await learn.sourcesForTopic(topic.id);
      expect(sources.single.kind, SourceKind.link);
      expect(sources.single.url, 'https://instagram.com/reel/abc');
    });

    test('text capture keeps the full text as a TXT source',
        () async {
      final topic = await capture.saveCapture(const SharedCapture(
        kind: CaptureKind.text,
        text: 'First line title\nThe body that must not be lost.',
      ));
      expect(topic.title, 'First line title');
      final sources = await learn.sourcesForTopic(topic.id);
      expect(sources.single.kind, SourceKind.txt);
      final content =
          await library.readText(sources.single.fileRelPath!);
      expect(content, contains('must not be lost'));
    });

    test('file capture imports the file as a source', () async {
      final shared = File('${tmp.path}/shared.txt');
      await shared.writeAsString('shared file body');
      final topic = await capture.saveCapture(SharedCapture(
        kind: CaptureKind.file,
        filePath: shared.path,
        fileName: 'shared.txt',
      ));
      final sources = await learn.sourcesForTopic(topic.id);
      expect(sources.single.kind, SourceKind.txt);
      expect(await library.readText(sources.single.fileRelPath!),
          'shared file body');
    });

    test('a hostile file name is sanitised on the way in', () async {
      final shared = File('${tmp.path}/x.txt');
      await shared.writeAsString('body');
      final topic = await capture.saveCapture(SharedCapture(
        kind: CaptureKind.file,
        filePath: shared.path,
        fileName: '../../evil.txt',
      ));
      final sources = await learn.sourcesForTopic(topic.id);
      expect(sources.single.fileRelPath, 'sources/evil.txt');
      expect(await File('${tmp.path}/evil.txt').exists(), isFalse);
    });

    test('the owner-edited title wins over the suggestion', () async {
      final topic = await capture.saveCapture(
        const SharedCapture(
            kind: CaptureKind.link, text: 'https://example.com/x'),
        title: 'My own title',
      );
      expect(topic.title, 'My own title');
    });
  });

  group('fake service (the UI seam)', () {
    test('cold + warm captures both arrive through the interface',
        () async {
      final controller = StreamController<SharedCapture>();
      final fake = FakeShareIntentService(
        [const SharedCapture(kind: CaptureKind.text, text: 'cold')],
        controller.stream,
      );
      expect((await fake.initialCaptures()).single.text, 'cold');
      final warm = fake.captures.first;
      controller.add(
          const SharedCapture(kind: CaptureKind.text, text: 'warm'));
      expect((await warm).text, 'warm');
      await fake.markConsumed();
      expect(fake.consumed, isTrue);
      await controller.close();
    });
  });

  group('suggested titles', () {
    test('long text truncates at 60 chars', () {
      final c = SharedCapture(
          kind: CaptureKind.text, text: 'a' * 100);
      expect(c.suggestedTitle.length, 61); // 60 + ellipsis
    });
  });
}
