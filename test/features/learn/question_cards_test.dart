// LEARN engine — question card widgets (S5 step C2a, §R4.1):
// one widget test per type, each driven to onResult with the
// correctness asserted and onResult proven to fire EXACTLY once.
//
// Driving patterns (reused by the C2b session-screen tests):
// - mcq / mythfact / ordering / scenario: tap the widget that
//   carries the answer TEXT (find.text) — choice order, chip
//   order and shuffle never matter.
// - flashcard / cloze: tap 'Show answer', then 'Got it' /
//   'Missed it'.
// - ordering: tap tray chips in the intended final order (each
//   tap appends), then 'Check order'.
// - scenario: tap choice buttons node by node; at the end node
//   tap 'See result'.
// - image_point: real file IO + image decoding need the real
//   event loop, so the test runs inside tester.runAsync and
//   POLLS (pump with a duration) instead of pumpAndSettle — the
//   same harness rule as the S3 Day Close widget test.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:daily_life_app/core/theme.dart';
import 'package:daily_life_app/features/learn/image_geometry.dart';
import 'package:daily_life_app/features/learn/learn_engine_store.dart';
import 'package:daily_life_app/features/learn/library_store.dart';
import 'package:daily_life_app/features/learn/pack_importer.dart';
import 'package:daily_life_app/features/learn/pack_media.dart';
import 'package:daily_life_app/features/learn/question_cards.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

LearnQuestion makeQuestion(
  String type,
  Map<String, Object?> payload, {
  String? packId,
}) =>
    LearnQuestion(
      id: 1,
      topicId: 1,
      packId: packId,
      type: type,
      payload: payload,
      difficulty: 3,
      ef: 2.5,
      reps: 0,
      lapses: 0,
      intervalDays: 0,
      dueAt: 0,
      suspended: false,
      createdAt: 0,
      updatedAt: 0,
    );

Widget host(Widget child) => MaterialApp(
      theme: AppTheme.forPlate(AppPlate.midnight),
      home: Scaffold(body: child),
    );

void main() {
  group('McqCard', () {
    const payload = <String, Object?>{
      'prompt': 'How do you say "Peace be upon you"?',
      'choices': [
        {'id': 'a', 'text': 'السلام عليكم'},
        {'id': 'b', 'text': 'شكراً'},
        {'id': 'c', 'text': 'مع السلامة'},
      ],
      'correctChoiceIds': ['a'],
      'shuffle': false,
      'explanation': 'The standard greeting.',
    };

    testWidgets('tapping the correct choice → correct, fires once',
        (tester) async {
      final results = <QuestionResult>[];
      await tester.pumpWidget(host(McqCard(
        question: makeQuestion('mcq', payload),
        onResult: results.add,
      )));
      await tester.tap(find.text('السلام عليكم'));
      await tester.pump();
      expect(results, hasLength(1));
      expect(results.single.correct, isTrue);
      expect(results.single.feedback, 'The standard greeting.');
      // A second tap after lock-in must not fire again.
      await tester.tap(find.text('شكراً'));
      await tester.pump();
      expect(results, hasLength(1));
    });

    testWidgets('tapping a wrong choice → incorrect', (tester) async {
      final results = <QuestionResult>[];
      await tester.pumpWidget(host(McqCard(
        question: makeQuestion('mcq', payload),
        onResult: results.add,
      )));
      await tester.tap(find.text('شكراً'));
      await tester.pump();
      expect(results, hasLength(1));
      expect(results.single.correct, isFalse);
    });
  });

  group('MythFactCard', () {
    testWidgets('statement is a fact → tapping FACT → correct',
        (tester) async {
      final results = <QuestionResult>[];
      await tester.pumpWidget(host(MythFactCard(
        question: makeQuestion('mythfact', const {
          'statement': 'شكراً (shukran) means thank you.',
          'isFact': true,
          'explanation': 'It does.',
        }),
        onResult: results.add,
      )));
      await tester.tap(find.text('FACT'));
      await tester.pump();
      expect(results, hasLength(1));
      expect(results.single.correct, isTrue);
      expect(results.single.feedback, 'It does.');
      await tester.tap(find.text('MYTH'));
      await tester.pump();
      expect(results, hasLength(1));
    });
  });

  group('FlashcardCard', () {
    testWidgets('Show answer → Got it → correct', (tester) async {
      final results = <QuestionResult>[];
      await tester.pumpWidget(host(FlashcardCard(
        question: makeQuestion('flashcard', const {
          'front': 'السلام عليكم',
          'back': 'Peace be upon you.',
        }),
        onResult: results.add,
      )));
      expect(find.text('Peace be upon you.'), findsNothing);
      await tester.tap(find.text('Show answer'));
      await tester.pump();
      expect(find.text('Peace be upon you.'), findsOneWidget);
      await tester.tap(find.text('Got it'));
      await tester.pump();
      expect(results, hasLength(1));
      expect(results.single.correct, isTrue);
      expect(results.single.feedback, isNull);
    });
  });

  group('ClozeCard', () {
    const answer = 'السلام عليكم';
    const payload = <String, Object?>{
      'text': 'The standard greeting is {{$answer}} at any time.',
    };

    testWidgets('answer hidden until reveal; Missed it → incorrect',
        (tester) async {
      final results = <QuestionResult>[];
      await tester.pumpWidget(host(ClozeCard(
        question: makeQuestion('cloze', payload),
        onResult: results.add,
      )));
      // The blank is shown; the answer string is nowhere in the tree.
      expect(find.textContaining('_____'), findsOneWidget);
      expect(find.textContaining(answer), findsNothing);
      await tester.tap(find.text('Show answer'));
      await tester.pump();
      expect(find.textContaining(answer), findsOneWidget);
      await tester.tap(find.text('Missed it'));
      await tester.pump();
      expect(results, hasLength(1));
      expect(results.single.correct, isFalse);
    });
  });

  group('OrderingCard', () {
    const payload = <String, Object?>{
      'prompt': 'Put this greeting exchange in order',
      'items': [
        {'id': 'i1', 'text': 'First greeting'},
        {'id': 'i2', 'text': 'Reply greeting'},
        {'id': 'i3', 'text': 'How are you'},
        {'id': 'i4', 'text': 'Fine thanks'},
      ],
      'correctOrder': ['i1', 'i2', 'i3', 'i4'],
      'explanation': 'Greeting, reply, question, answer.',
    };

    Future<void> tapInOrder(WidgetTester tester, List<String> texts) async {
      for (final text in texts) {
        await tester.tap(find.text(text));
        await tester.pump();
      }
    }

    testWidgets('tapping items in the correct order → correct',
        (tester) async {
      final results = <QuestionResult>[];
      await tester.pumpWidget(host(OrderingCard(
        question: makeQuestion('ordering', payload),
        onResult: results.add,
      )));
      // Check stays disabled until the answer is complete.
      final checkButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Check order'),
      );
      expect(checkButton.onPressed, isNull);
      await tapInOrder(tester, [
        'First greeting',
        'Reply greeting',
        'How are you',
        'Fine thanks',
      ]);
      await tester.tap(find.text('Check order'));
      await tester.pump();
      expect(results, hasLength(1));
      expect(results.single.correct, isTrue);
      expect(results.single.feedback, 'Greeting, reply, question, answer.');
    });

    testWidgets('tapping items in the wrong order → incorrect',
        (tester) async {
      final results = <QuestionResult>[];
      await tester.pumpWidget(host(OrderingCard(
        question: makeQuestion('ordering', payload),
        onResult: results.add,
      )));
      await tapInOrder(tester, [
        'Fine thanks',
        'How are you',
        'Reply greeting',
        'First greeting',
      ]);
      await tester.tap(find.text('Check order'));
      await tester.pump();
      expect(results, hasLength(1));
      expect(results.single.correct, isFalse);
    });
  });

  group('ScenarioCard', () {
    // The sample fixture's scenario shape (§R4.1 branch-and-
    // bottleneck), with per-choice scores added.
    Map<String, Object?> scenarioPayload() => <String, Object?>{
          'startNode': 'n1',
          'nodes': <String, Object?>{
            'n1': <String, Object?>{
              'text': 'You push open the café door. How do you greet him?',
              'choices': [
                <String, Object?>{
                  'text': 'صباح الخير، كيف حالك؟',
                  'next': 'n2',
                  'score': 1,
                  'feedback': 'A warm morning greeting.',
                },
                <String, Object?>{
                  'text': 'مع السلامة!',
                  'next': 'n3',
                  'score': 0,
                  'feedback': 'That means goodbye.',
                },
              ],
            },
            'n2': <String, Object?>{
              'text': 'He replies and asks what you would like.',
              'choices': [
                <String, Object?>{'text': 'شكراً جزيلاً', 'next': 'n4'},
              ],
            },
            'n3': <String, Object?>{
              'text': 'You laugh and correct the greeting.',
              'choices': [
                <String, Object?>{'text': 'آسف! صباح الخير', 'next': 'n4'},
              ],
            },
            'n4': <String, Object?>{
              'end': true,
              'text': 'You sip your tea as the café fills up.',
              'summary': 'Morning greetings debrief.',
            },
          },
        };

    testWidgets('score-1 path → debrief → See result → correct',
        (tester) async {
      final results = <QuestionResult>[];
      await tester.pumpWidget(host(ScenarioCard(
        question: makeQuestion('scenario', scenarioPayload()),
        onResult: results.add,
      )));
      expect(
        find.text('You push open the café door. How do you greet him?'),
        findsOneWidget,
      );
      await tester.tap(find.text('صباح الخير، كيف حالك؟'));
      await tester.pump();
      // Choice feedback shows as a muted system line; next node arrived.
      expect(find.text('A warm morning greeting.'), findsOneWidget);
      expect(
        find.text('He replies and asks what you would like.'),
        findsOneWidget,
      );
      await tester.tap(find.text('شكراً جزيلاً'));
      await tester.pump();
      // End node: its text AND the debrief summary are in the tree.
      expect(find.text('You sip your tea as the café fills up.'),
          findsOneWidget);
      expect(find.text('Morning greetings debrief.'), findsOneWidget);
      expect(results, isEmpty);
      await tester.tap(find.text('See result'));
      await tester.pump();
      expect(results, hasLength(1));
      expect(results.single.correct, isTrue);
      expect(results.single.feedback, 'Morning greetings debrief.');
    });

    testWidgets('choosing a score-0 choice → incorrect', (tester) async {
      final results = <QuestionResult>[];
      await tester.pumpWidget(host(ScenarioCard(
        question: makeQuestion('scenario', scenarioPayload()),
        onResult: results.add,
      )));
      await tester.tap(find.text('مع السلامة!'));
      await tester.pump();
      await tester.tap(find.text('آسف! صباح الخير'));
      await tester.pump();
      await tester.tap(find.text('See result'));
      await tester.pump();
      expect(results, hasLength(1));
      expect(results.single.correct, isFalse);
    });
  });

  group('ImagePointCard', () {
    const payload = <String, Object?>{
      'prompt': 'Tap the centre',
      'image': 'm1',
      'target': {'cx': 0.5, 'cy': 0.5, 'r': 0.2},
      'explanation': 'The middle.',
    };

    /// A real 200×100 PNG, painted offscreen.
    Future<List<int>> buildPngBytes() async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 200, 100),
        Paint()..color = const Color(0xFF336699),
      );
      final picture = recorder.endRecording();
      final image = await picture.toImage(200, 100);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData!.buffer.asUint8List();
    }

    /// Poll with real delays (inside runAsync) until [cond] holds.
    Future<bool> pollUntil(WidgetTester tester, bool Function() cond) async {
      for (var i = 0; i < 50; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 50));
        if (cond()) return true;
      }
      return false;
    }

    Future<({Directory tmp, LibraryStore library})> setUpLibrary(
      List<int> pngBytes,
    ) async {
      final tmp = await Directory.systemTemp.createTemp('nimo-c2a-');
      final library = LibraryStore(Directory('${tmp.path}/Library'));
      await library.ensureLayout();
      await library.writeAtomic(
        PackImporter.mediaRelPath('p1', 'm1', 'image/png'),
        pngBytes,
      );
      return (tmp: tmp, library: library);
    }

    Widget imageHost(
      List<QuestionResult> results,
      Future<File?> imageFile,
    ) =>
        MaterialApp(
          theme: AppTheme.forPlate(AppPlate.midnight),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                height: 600,
                child: ImagePointCard(
                  question: makeQuestion('image_point', payload, packId: 'p1'),
                  onResult: results.add,
                  imageFile: imageFile,
                ),
              ),
            ),
          ),
        );

    testWidgets('tap the VISUAL centre of a letterboxed image → correct',
        (tester) async {
      await tester.runAsync(() async {
        final png = await buildPngBytes();
        final setup = await setUpLibrary(png);
        try {
          final question =
              makeQuestion('image_point', payload, packId: 'p1');
          final results = <QuestionResult>[];
          await tester.pumpWidget(
            imageHost(results, resolveQuestionImage(setup.library, question)),
          );
          // Wait until the surface has discovered the image size
          // and actually renders the image.
          expect(
            await pollUntil(
              tester,
              () => find.byType(Image).evaluate().isNotEmpty,
            ),
            isTrue,
            reason: 'image never rendered',
          );
          // Compute the DISPLAYED image rect and tap its centre —
          // the box is much taller than the image aspect, so the
          // image is letterboxed and the box centre ≠ naive taps.
          final surface = find.byType(ImagePointSurface);
          final topLeft = tester.getTopLeft(surface);
          final size = tester.getSize(surface);
          final displayed = containRect(size, const Size(200, 100));
          expect(displayed.height, lessThan(size.height)); // letterboxed
          await tester.tapAt(topLeft + displayed.center);
          await pollUntil(tester, () => results.isNotEmpty);
          // Aspect loading races the surface on some runs: if the
          // first tap landed before grading armed, tap once more.
          if (results.isEmpty) {
            await tester.tapAt(topLeft + displayed.center);
            await pollUntil(tester, () => results.isNotEmpty);
          }
          expect(results, hasLength(1));
          expect(results.single.correct, isTrue);
          expect(results.single.feedback, 'The middle.');
        } finally {
          await setup.tmp.delete(recursive: true);
        }
      });
    });

    testWidgets('tap a far corner of the image → incorrect', (tester) async {
      await tester.runAsync(() async {
        final png = await buildPngBytes();
        final setup = await setUpLibrary(png);
        try {
          final question =
              makeQuestion('image_point', payload, packId: 'p1');
          final results = <QuestionResult>[];
          await tester.pumpWidget(
            imageHost(results, resolveQuestionImage(setup.library, question)),
          );
          expect(
            await pollUntil(
              tester,
              () => find.byType(Image).evaluate().isNotEmpty,
            ),
            isTrue,
            reason: 'image never rendered',
          );
          final surface = find.byType(ImagePointSurface);
          final topLeft = tester.getTopLeft(surface);
          final size = tester.getSize(surface);
          final displayed = containRect(size, const Size(200, 100));
          final cornerTap =
              topLeft + displayed.topLeft + const Offset(8, 8);
          await tester.tapAt(cornerTap);
          await pollUntil(tester, () => results.isNotEmpty);
          if (results.isEmpty) {
            await tester.tapAt(cornerTap);
            await pollUntil(tester, () => results.isNotEmpty);
          }
          expect(results, hasLength(1));
          expect(results.single.correct, isFalse);
        } finally {
          await setup.tmp.delete(recursive: true);
        }
      });
    });

    testWidgets('missing media → Mark as missed → incorrect with note',
        (tester) async {
      final results = <QuestionResult>[];
      await tester.pumpWidget(host(ImagePointCard(
        question: makeQuestion(
          'image_point',
          payload,
          packId: 'p1',
        ),
        onResult: results.add,
        imageFile: Future.value(null),
      )));
      await tester.pump();
      expect(find.text('Image missing for this question.'), findsOneWidget);
      await tester.tap(find.text('Mark as missed'));
      await tester.pump();
      expect(results, hasLength(1));
      expect(results.single.correct, isFalse);
      expect(
        results.single.feedback,
        'The image file is missing from the Library.',
      );
    });
  });
}
