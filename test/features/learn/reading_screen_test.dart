// STEP 6 — ReadingScreen behaviour tests (audit finding 007).
// Same harness as topics_screen_test.dart. Reading loads go
// through ImportService.readablePages: txt sources read their
// Library file; anything unreadable degrades to "no text".
import 'dart:convert';
import 'dart:io';

import 'package:daily_life_app/core/db/app_database.dart';
import 'package:daily_life_app/core/theme.dart';
import 'package:daily_life_app/features/learn/learn_services.dart';
import 'package:daily_life_app/features/learn/learn_store.dart';
import 'package:daily_life_app/features/learn/library_store.dart';
import 'package:daily_life_app/features/learn/reading_screen.dart';
import 'package:daily_life_app/features/store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> _wipe(Database db) async {
  for (final t in [
    'review_log',
    'questions',
    'learn_sessions',
    'packs',
    'marked_points',
    'sources',
    'topics',
    'items',
    'checklist_entries',
    'projects',
    'workspaces',
    'day_reviews',
    'shield_events',
    'day_plan_items',
    'day_plans',
    'plan_templates',
    'app_settings',
  ]) {
    await db.delete(t);
  }
}

/// 210 filler words — enough, with a second paragraph, to force
/// chunkText past its 200-word buffer into a second card.
String filler(String tag) => [
  for (var s = 0; s < 3; s++)
    '${List.generate(60, (i) => '$tag${s}x$i').join(' ')}.',
  List.generate(30, (i) => '$tag-end$i').join(' '),
].join('. '); // 3x60 + 30 = 210 words, 4 sentences

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<({LearnServices learn, Source source})> seed({
    required bool withFile,
    String status = ExtractionStatus.ok,
    bool twoCards = false,
  }) async {
    final db = await AppDatabase.openInMemory();
    await _wipe(db);
    final tmp = await Directory.systemTemp.createTemp('nimo-reading-');
    addTearDown(() => tmp.delete(recursive: true));
    final library = LibraryStore(Directory('${tmp.path}/Library'));
    await library.ensureLayout();
    final learnStore = LearnStore(db);
    final learn = LearnServices(learnStore, library, db: db);
    final store = Store(db);
    final ws = await store.createWorkspace('Learning');
    final prj = await store.createProject(ws.id, 'Arabic');
    final topic = await learnStore.createTopic(
      projectId: prj.id,
      title: 'Reading',
    );
    if (withFile) {
      final body = twoCards
          ? 'Alpha opening line.\n\n${filler('w')}\n\nOmega closing line.'
          : 'Assalamu alaikum. This is the first lesson body.';
      await library.writeAtomic('sources/lesson.txt', utf8.encode(body));
    }
    final source = await learnStore.addSource(
      topicId: topic.id,
      kind: SourceKind.txt,
      title: 'Lesson One',
      fileRelPath: 'sources/lesson.txt',
      extractionStatus: status,
    );
    return (learn: learn, source: source);
  }

  Widget app(LearnServices learn, Source source) => MaterialApp(
    theme: AppTheme.forPlate(AppPlate.midnight),
    home: ReadingScreen(learn: learn, source: source),
  );

  Future<void> pumpUntil(WidgetTester tester, Finder f) async {
    for (var i = 0; i < 30; i++) {
      if (f.evaluate().isNotEmpty) return;
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await tester.pump();
    }
    fail('Timed out waiting for $f');
  }

  testWidgets('R1: a txt source renders its text on card 1', (tester) async {
    await tester.runAsync(() async {
      final s = await seed(withFile: true);
      await tester.pumpWidget(app(s.learn, s.source));
      await pumpUntil(
        tester,
        find.textContaining('This is the first lesson body'),
      );
      expect(find.text('Lesson One'), findsOneWidget); // AppBar title
      expect(find.text('Card 1 of 1'), findsOneWidget);
      // Single card: both nav buttons disabled.
      final prev = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Prev'),
      );
      final next = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Next'),
      );
      expect(prev.onPressed, isNull);
      expect(next.onPressed, isNull);
    });
  });

  testWidgets('R4: Next/Prev move between cards', (tester) async {
    await tester.runAsync(() async {
      final s = await seed(withFile: true, twoCards: true);
      await tester.pumpWidget(app(s.learn, s.source));
      // Fixture chunking (measured against chunkText, see the
      // filler comment): card 1 = alpha + filler sentences 1-3,
      // card 2 = filler tail, card 3 = omega alone.
      String bodyText() => tester
          .widgetList<EditableText>(find.byType(EditableText))
          .map((e) => e.controller.text)
          .join('\n');
      await pumpUntil(tester, find.text('Card 1 of 3'));
      expect(bodyText().contains('Alpha opening line'), isTrue);
      expect(
        find.textContaining('Alpha opening line'),
        findsWidgets,
      ); // body + marking-UI sentence chip

      await tester.tap(find.text('Next'));
      await tester.pump();
      await pumpUntil(tester, find.text('Card 2 of 3'));
      expect(bodyText().contains('w-end29'), isTrue);
      expect(bodyText().contains('Alpha opening line'), isFalse);

      await tester.tap(find.text('Next'));
      await tester.pump();
      await pumpUntil(tester, find.text('Card 3 of 3'));
      expect(bodyText().contains('Omega closing line'), isTrue);
      final next = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Next'),
      );
      expect(next.onPressed, isNull); // last card

      await tester.tap(find.text('Prev'));
      await tester.pump();
      await pumpUntil(tester, find.text('Card 2 of 3'));
      await tester.tap(find.text('Prev'));
      await tester.pump();
      await pumpUntil(tester, find.text('Card 1 of 3'));
      expect(bodyText().contains('Alpha opening line'), isTrue);
      final prev = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Prev'),
      );
      expect(prev.onPressed, isNull); // first card
    });
  });

  testWidgets('R2a: a missing file shows the honest no-text state', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final s = await seed(withFile: false);
      await tester.pumpWidget(app(s.learn, s.source));
      await pumpUntil(tester, find.text('Text extracted'));
      // readablePages degrades a vanished file to null pages, so
      // the screen shows its no-text state (ExtractionStatus
      // describe line) — never a spinner, never a crash.
      expect(
        find.text(
          'The file itself is in your Library — open the '
          'source to view it directly.',
        ),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  testWidgets('R2b: a failed-extraction source shows its honest '
      'status line', (tester) async {
    await tester.runAsync(() async {
      final s = await seed(withFile: false, status: ExtractionStatus.failed);
      await tester.pumpWidget(app(s.learn, s.source));
      await pumpUntil(
        tester,
        find.text('Text extraction failed for this file'),
      );
      expect(
        find.text(
          'The file itself is in your Library — open the '
          'source to view it directly.',
        ),
        findsOneWidget,
      );
    });
  });
}
