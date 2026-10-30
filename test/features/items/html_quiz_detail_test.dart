// HTML quiz — detail body + player platform gate (S5 legacy
// player). The detail screen shows the Play quiz button; the
// player itself is NOT pumped into its WebView (platform views
// cannot run on the host) — only its non-Android message path
// is pumped, which is deterministic on a Linux host
// (Platform.isAndroid is false).
import 'dart:io';

import 'package:daily_life_app/core/db/app_database.dart';
import 'package:daily_life_app/features/items/html_quiz/html_quiz_player_screen.dart';
import 'package:daily_life_app/features/items/item_detail_screen.dart';
import 'package:daily_life_app/features/learn/learn_services.dart';
import 'package:daily_life_app/features/learn/learn_store.dart';
import 'package:daily_life_app/features/learn/library_store.dart';
import 'package:daily_life_app/features/store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('ItemDetailScreen for an html_quiz item shows Play quiz',
      (tester) async {
    await tester.runAsync(() async {
      final db = await AppDatabase.openInMemory();
      final tmp = await Directory.systemTemp.createTemp('nimo-htmlq-');
      try {
        final library = LibraryStore(Directory('${tmp.path}/Library'));
        await library.ensureLayout();
        final learn = LearnServices(LearnStore(db), library, db: db);
        final store = Store(db);
        final ws = await store.createWorkspace('W');
        final prj = await store.createProject(ws.id, 'P');
        final item = await store.createItem(
          prj.id,
          type: ItemType.htmlQuiz,
          title: 'My Quiz',
          payload: {'file_rel_path': 'html_quizzes/quiz.html'},
        );

        await tester.pumpWidget(MaterialApp(
          home: ItemDetailScreen(store: store, item: item, learn: learn),
        ));
        await tester.pump();

        expect(find.text('Play quiz'), findsOneWidget);
        expect(find.widgetWithText(FilledButton, 'Play quiz'),
            findsOneWidget);
        expect(find.text('quiz.html'), findsOneWidget);
      } finally {
        await tmp.delete(recursive: true);
      }
    });
  });

  testWidgets(
      'player shows the desktop browser fallback on a non-Android host '
      '(S7; was the Android-only message in S5)', (tester) async {
    await tester.runAsync(() async {
      final tmp = await Directory.systemTemp.createTemp('nimo-htmlp-');
      try {
        final library = LibraryStore(Directory('${tmp.path}/Library'));
        await library.ensureLayout();
        await library.writeAtomic(
            'html_quizzes/quiz.html', '<html></html>'.codeUnits);

        await tester.pumpWidget(MaterialApp(
          home: HtmlQuizPlayerScreen(
            library: library,
            payload: const {'file_rel_path': 'html_quizzes/quiz.html'},
            title: 'My Quiz',
          ),
        ));
        await tester.pump();

        expect(find.text('On desktop, HTML quizzes open in your browser.'),
            findsOneWidget);
        expect(find.text('Open in browser'), findsOneWidget);
      } finally {
        await tmp.delete(recursive: true);
      }
    });
  });

  testWidgets('player with a missing file shows an error, never crashes',
      (tester) async {
    await tester.runAsync(() async {
      final tmp = await Directory.systemTemp.createTemp('nimo-htmlm-');
      try {
        final library = LibraryStore(Directory('${tmp.path}/Library'));
        await library.ensureLayout();

        await tester.pumpWidget(MaterialApp(
          home: HtmlQuizPlayerScreen(
            library: library,
            payload: const {'file_rel_path': 'html_quizzes/gone.html'},
            title: 'Gone',
          ),
        ));
        await tester.pump();

        expect(find.text('This quiz file could not be found.'),
            findsOneWidget);
      } finally {
        await tmp.delete(recursive: true);
      }
    });
  });
}
