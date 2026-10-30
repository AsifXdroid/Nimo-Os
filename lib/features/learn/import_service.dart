/// LEARN-data — importing material into a topic (§R4.5 pipeline).
///
/// Import document → stored in the Library as a *source* under a
/// *topic* → text layer extracted once → status recorded honestly
/// (`ok` / `partial` / `scanned_no_text` / `failed`). A document
/// whose extraction fails is still imported — the file itself is
/// readable in the viewer; only its reading cards are missing.
library;

import 'dart:convert';

import 'package:path/path.dart' as p;

import 'learn_store.dart';
import 'library_store.dart';
import 'text_extract.dart';

class ImportService {
  ImportService(this._learn, this._library,
      {this.pdfExtractor = pdfrxPageTexts});

  final LearnStore _learn;
  final LibraryStore _library;
  final PdfPageTextExtractor pdfExtractor;

  /// Map a filename to a source kind by extension.
  static String kindForFileName(String name) {
    return switch (p.extension(name).toLowerCase()) {
      '.pdf' => SourceKind.pdf,
      '.txt' || '.md' => SourceKind.txt,
      '.html' || '.htm' => SourceKind.htmlQuiz,
      '.quizpack' || '.zip' => SourceKind.pack,
      _ => SourceKind.file,
    };
  }

  /// Import an external file as a source of [topicId]. [title]
  /// defaults to the (sanitised) filename — a manual title always
  /// wins over any fetched/guessed one (§R4.5).
  Future<Source> importFile({
    required int topicId,
    required String sourcePath,
    required String originalName,
    String? title,
  }) async {
    final kind = kindForFileName(originalName);
    final rel = await _library.importFile('sources', sourcePath, originalName);
    var source = await _learn.addSource(
      topicId: topicId,
      kind: kind,
      title: (title == null || title.trim().isEmpty)
          ? p.basenameWithoutExtension(LibraryStore.sanitizeFileName(originalName))
          : title.trim(),
      fileRelPath: rel,
      extractionStatus: ExtractionStatus.failed, // until extraction runs
    );
    source = await _extractAndRecord(source);
    return source;
  }

  /// Store shared/typed text as a TXT source of [topicId] (the
  /// text itself is the material — e.g. a share-intent text
  /// capture). The file lands in the Library like any import.
  Future<Source> importTextContent({
    required int topicId,
    required String text,
    required String title,
  }) async {
    final rel = await _library.importBytes(
      'sources',
      utf8.encode(text),
      '${LibraryStore.sanitizeFileName(title)}.txt',
    );
    return _learn.addSource(
      topicId: topicId,
      kind: SourceKind.txt,
      title: title.trim().isEmpty ? 'Shared text' : title.trim(),
      fileRelPath: rel,
      extractionStatus: ExtractionStatus.ok,
    );
  }

  /// Attach a link as a source of [topicId].
  Future<Source> importLink({
    required int topicId,
    required String url,
    String? title,
  }) async {
    final clean = url.trim();
    return _learn.addSource(
      topicId: topicId,
      kind: SourceKind.link,
      title: (title == null || title.trim().isEmpty) ? clean : title.trim(),
      url: clean,
    );
  }

  /// (Re)run extraction for a file-backed source and record the
  /// outcome + sidecar. Returns the updated source.
  Future<Source> _extractAndRecord(Source source) async {
    final rel = source.fileRelPath;
    if (rel == null) return source;
    final file = _library.resolve(rel);
    // PDF extraction works from the file path (pdfrx); only the
    // text kinds need their bytes in memory — don't read a whole
    // PDF into RAM for nothing.
    final bytes = source.kind == SourceKind.pdf
        ? const <int>[]
        : await file.readAsBytes();
    final outcome = await extractDocumentText(
      kind: source.kind,
      filePath: file.path,
      bytes: bytes,
      pdfExtractor: pdfExtractor,
    );
    String? textRel;
    if (source.kind == SourceKind.pdf &&
        outcome.pageTexts.isNotEmpty) {
      // Sidecar next to the PDF: extraction runs once (§R6.1).
      // The source id is part of the name so a sidecar can never
      // collide with (or overwrite) another source's file that
      // happens to share the derived name.
      final sidecarName =
          '${p.basenameWithoutExtension(rel)}.${source.id}.extracted.json';
      textRel = 'sources/$sidecarName';
      await _library.writeAtomic(textRel, utf8.encode(outcome.encodeSidecar()));
    }
    await _learn.updateSourceExtraction(
      source.id,
      extractionStatus: outcome.status,
      textRelPath: textRel,
    );
    return _learn.sourceById(source.id);
  }

  /// The extracted page texts a reader should show for [source]:
  /// PDF → the sidecar; TXT → the file itself. Null when there is
  /// no readable text (the UI then shows the status line instead).
  Future<List<String>?> readablePages(Source source) async {
    if (!source.hasReadableText) return null;
    try {
      if (source.kind == SourceKind.pdf) {
        final rel = source.textRelPath;
        if (rel == null) return null;
        return ExtractionOutcome.decodeSidecar(await _library.readText(rel));
      }
      if (source.kind == SourceKind.txt) {
        final rel = source.fileRelPath;
        if (rel == null) return null;
        return [decodeTxtBytes(await _library.readBytes(rel))];
      }
    } catch (_) {
      // Any corruption — malformed sidecar JSON, a stored path
      // that no longer resolves, a vanished file — degrades to
      // "no readable text", never a crash or an endless spinner.
      // The source row still carries its honest status line.
      return null;
    }
    return null;
  }
}
