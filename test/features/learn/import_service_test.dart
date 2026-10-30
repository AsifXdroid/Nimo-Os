// LEARN-data — ImportService + text extraction (S4, §R4.5):
// the adversarial-import suite (TESTING.md §9/S4) — malformed
// UTF-8, empty files, truncated/extractor-failing PDFs and
// scanned (textless) PDFs all land as honest statuses with the
// file safe in the Library; nothing crashes, nothing is written
// partially. PDF extraction runs through a FAKE extractor here —
// the real pdfrx engine wiring is device-verified (see
// PROGRESS_LOG).
import 'dart:convert';
import 'dart:io';

import 'package:daily_life_app/core/db/app_database.dart';
import 'package:daily_life_app/features/learn/import_service.dart';
import 'package:daily_life_app/features/learn/learn_store.dart';
import 'package:daily_life_app/features/learn/library_store.dart';
import 'package:daily_life_app/features/learn/text_extract.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// ~450 words over several paragraphs: enough for multiple cards.
String longText() {
  // One sentence = 10 words; one paragraph = 18 sentences (180
  // words); four paragraphs = 720 words → four ~180-word cards.
  final para = List.filled(
          18, 'Arabic verbs follow patterns that repeat across roots daily.')
      .join(' ');
  return [para, para, para, para].join('\n\n');
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tmp;
  late LearnStore learn;
  late LibraryStore library;
  late int topicId;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('nimo-import-');
    final db = await AppDatabase.openInMemory();
    learn = LearnStore(db);
    library = LibraryStore(Directory('${tmp.path}/Library'));
    await library.ensureLayout();
    final inbox = await learn.ensureInboxProject();
    topicId =
        (await learn.createTopic(projectId: inbox.id, title: 'T')).id;
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  ImportService serviceWith(PdfPageTextExtractor extractor) =>
      ImportService(learn, library, pdfExtractor: extractor);

  Future<File> incoming(String name, List<int> bytes) async {
    final f = File('${tmp.path}/$name');
    await f.writeAsBytes(bytes);
    return f;
  }

  group('TXT imports', () {
    test('a UTF-8 TXT imports ok and is readable in full', () async {
      final f = await incoming('notes.txt', utf8.encode(longText()));
      final imports = serviceWith((_) async => const []);
      final source = await imports.importFile(
          topicId: topicId, sourcePath: f.path, originalName: 'notes.txt');
      expect(source.kind, SourceKind.txt);
      expect(source.extractionStatus, ExtractionStatus.ok);
      expect(source.fileRelPath, 'sources/notes.txt');
      final pages = await imports.readablePages(source);
      expect(pages, isNotNull);
      expect(pages!.single, contains('Arabic verbs'));
    });

    test('a BOM-prefixed TXT decodes cleanly', () async {
      final bytes = [0xEF, 0xBB, 0xBF, ...utf8.encode('hello world')];
      final f = await incoming('bom.txt', bytes);
      final imports = serviceWith((_) async => const []);
      final source = await imports.importFile(
          topicId: topicId, sourcePath: f.path, originalName: 'bom.txt');
      expect(source.extractionStatus, ExtractionStatus.ok);
      final pages = await imports.readablePages(source);
      expect(pages!.single, 'hello world');
    });

    test('malformed UTF-8 fails cleanly: status failed, file kept, '
        'no partial text', () async {
      final f = await incoming('bad.txt', [0xC3, 0x28, 0xFF, 0x41]);
      final imports = serviceWith((_) async => const []);
      final source = await imports.importFile(
          topicId: topicId, sourcePath: f.path, originalName: 'bad.txt');
      expect(source.extractionStatus, ExtractionStatus.failed);
      expect(await library.exists(source.fileRelPath!), isTrue);
      expect(await imports.readablePages(source), isNull);
    });

    test('an empty TXT is failed, not an empty reading card',
        () async {
      final f = await incoming('empty.txt', []);
      final imports = serviceWith((_) async => const []);
      final source = await imports.importFile(
          topicId: topicId, sourcePath: f.path, originalName: 'empty.txt');
      expect(source.extractionStatus, ExtractionStatus.failed);
    });
  });

  group('PDF imports (fake extractor)', () {
    test('born-digital PDF: ok, sidecar written, pages readable',
        () async {
      final f = await incoming('book.pdf', [0x25, 0x50, 0x44, 0x46]);
      final imports = serviceWith(
          (_) async => ['Page one text.', 'Page two text.']);
      final source = await imports.importFile(
          topicId: topicId, sourcePath: f.path, originalName: 'book.pdf');
      expect(source.extractionStatus, ExtractionStatus.ok);
      expect(source.textRelPath,
          'sources/book.${source.id}.extracted.json');
      expect(await library.exists(source.textRelPath!), isTrue);
      final pages = await imports.readablePages(source);
      expect(pages, ['Page one text.', 'Page two text.']);
    });

    test('a scanned PDF is flagged scanned_no_text, never garbled',
        () async {
      final f = await incoming('scan.pdf', [1, 2, 3]);
      final imports = serviceWith((_) async => ['', '   ', '']);
      final source = await imports.importFile(
          topicId: topicId, sourcePath: f.path, originalName: 'scan.pdf');
      expect(source.extractionStatus, ExtractionStatus.scannedNoText);
      expect(source.textRelPath, isNull);
      expect(await imports.readablePages(source), isNull);
      // The file itself is still in the Library for the viewer.
      expect(await library.exists(source.fileRelPath!), isTrue);
    });

    test('mixed pages are partial', () async {
      final f = await incoming('mix.pdf', [1, 2, 3]);
      final imports =
          serviceWith((_) async => ['Real text here.', '']);
      final source = await imports.importFile(
          topicId: topicId, sourcePath: f.path, originalName: 'mix.pdf');
      expect(source.extractionStatus, ExtractionStatus.partial);
    });

    test('an extractor explosion (truncated PDF) is failed, '
        'import still completes', () async {
      final f = await incoming('trunc.pdf', [0x25, 0x50]);
      final imports = serviceWith(
          (_) async => throw StateError('PDFium: truncated'));
      final source = await imports.importFile(
          topicId: topicId, sourcePath: f.path, originalName: 'trunc.pdf');
      expect(source.extractionStatus, ExtractionStatus.failed);
      expect(await library.exists(source.fileRelPath!), isTrue);
    });
  });

  group('chunking + sentences', () {
    test('long text chunks into ~120–200 word cards with '
        'monotonic offsets', () {
      final text = longText();
      final chunks = chunkText(text);
      expect(chunks.length, greaterThan(1));
      for (final c in chunks) {
        final words =
            c.text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
        expect(words, lessThanOrEqualTo(220), reason: 'card too big');
        expect(words, greaterThanOrEqualTo(50), reason: 'card too small');
        expect(text.substring(c.startOffset).startsWith(
            c.text.substring(0, 20)), isTrue,
            reason: 'offset must point at the chunk text');
      }
      for (var i = 1; i < chunks.length; i++) {
        expect(chunks[i].startOffset,
            greaterThan(chunks[i - 1].startOffset));
        expect(chunks[i].index, chunks[i - 1].index + 1);
      }
    });

    test('paged chunks carry 1-based page numbers', () {
      final chunks = chunksForPages(['Short page one.', 'Short page two.'],
          paged: true);
      expect(chunks.map((c) => c.page), contains(1));
      expect(chunks.map((c) => c.page), contains(2));
      final unpaged = chunksForPages(['Whole file.'], paged: false);
      expect(unpaged.single.page, isNull);
    });

    test('splitSentences handles Latin and Arabic terminators', () {
      expect(splitSentences('One. Two? Three!'),
          ['One.', 'Two?', 'Three!']);
      expect(splitSentences('First sentence here. And a second one'),
          ['First sentence here.', 'And a second one']);
      expect(splitSentences('هل هذا صحيح؟ نعم هذا صحيح.'),
          ['هل هذا صحيح؟', 'نعم هذا صحيح.']);
    });
  });

  group('mark-a-point end-to-end (TXT fixture)', () {
    test('reading → mark → the point is stored with its offset',
        () async {
      const sentence = 'Patterns repeat across roots and reveal the system.';
      final text = 'Intro line. $sentence Closing line here.';
      final f = await incoming('lesson.txt', utf8.encode(text));
      final imports = serviceWith((_) async => const []);
      final source = await imports.importFile(
          topicId: topicId, sourcePath: f.path, originalName: 'lesson.txt');
      final pages = await imports.readablePages(source);
      final chunks = chunksForPages(pages!, paged: false);
      final chunk = chunks.single;
      final span = 'Patterns repeat';
      final mark = await learn.markPoint(
        sourceId: source.id,
        topicId: topicId,
        sentence: sentence,
        spanText: span,
        page: chunk.page,
        charOffset: chunk.spanOffset(sentence, span),
        chunkIndex: chunk.index,
      );
      expect(mark.page, isNull); // TXT: whole-file text
      expect(mark.charOffset, text.indexOf('Patterns'));
      expect(mark.clozeText,
          '_____ across roots and reveal the system.');
      final stored = await learn.markedPointsForTopic(topicId);
      expect(stored.single.sentence, sentence);
    });
  });

  group('links and text content', () {
    test('importLink stores the URL; manual title wins', () async {
      final imports = serviceWith((_) async => const []);
      final s = await imports.importLink(
          topicId: topicId,
          url: 'https://example.com/a',
          title: 'My title');
      expect(s.kind, SourceKind.link);
      expect(s.title, 'My title');
      expect(s.url, 'https://example.com/a');
    });

    test('importTextContent writes a readable TXT source', () async {
      final imports = serviceWith((_) async => const []);
      final s = await imports.importTextContent(
          topicId: topicId, text: 'Shared wisdom here.', title: 'Note');
      expect(s.kind, SourceKind.txt);
      final pages = await imports.readablePages(s);
      expect(pages!.single, 'Shared wisdom here.');
    });
  });
}
