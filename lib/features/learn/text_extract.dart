/// LEARN-data — text extraction + reading-card chunking (§R4.5).
///
/// Honest limits, by design: a PDF's text layer is all we get —
/// scanned PDFs have none, and that is reported as
/// [ExtractionStatus.scannedNoText], never as empty content. TXT
/// is UTF-8 (BOM tolerated); an undecodable file is `failed`,
/// never silently imported as mojibake (D-018).
///
/// The PDF engine sits behind [PdfPageTextExtractor] so every
/// rule here is host-testable with a fake; the real implementation
/// is [pdfrxPageTexts] (pdfrx_engine, PDFium — §R8.3).
library;

import 'dart:convert';

import 'package:pdfrx_engine/pdfrx_engine.dart';

import 'learn_store.dart';

/// Extracts the text of every page of a PDF (1 entry per page).
typedef PdfPageTextExtractor = Future<List<String>> Function(String path);

/// Real extractor (§R8.3): pdfrx_engine's `loadText()` per page.
Future<List<String>> pdfrxPageTexts(String path) async {
  final doc = await PdfDocument.openFile(path);
  try {
    final texts = <String>[];
    for (final page in doc.pages) {
      final raw = await page.loadText();
      texts.add(raw?.fullText ?? '');
    }
    return texts;
  } finally {
    await doc.dispose();
  }
}

/// One reading card: ~120–200 words of extracted text (§R4.5).
class ReadingChunk {
  const ReadingChunk({
    required this.index,
    required this.text,
    required this.page,
    required this.startOffset,
  });

  /// Position in the source's chunk sequence (0-based).
  final int index;
  final String text;

  /// 1-based PDF page, or null for TXT.
  final int? page;

  /// Offset of this chunk's first character within its page's
  /// (PDF) or the file's (TXT) extracted text.
  final int startOffset;

  /// Char offset of [span] (inside [sentence], inside this chunk)
  /// in the page/file text — the marked-point offset (§R8.3).
  int spanOffset(String sentence, String span) {
    final s = text.indexOf(sentence);
    if (s < 0) return startOffset;
    final within = sentence.indexOf(span);
    return startOffset + s + (within < 0 ? 0 : within);
  }
}

/// The result of running extraction over one document.
class ExtractionOutcome {
  const ExtractionOutcome({
    required this.status,
    required this.pageTexts,
  });

  final String status;

  /// One entry per PDF page; a single entry (the whole text) for
  /// TXT. Empty when [status] is scannedNoText/failed.
  final List<String> pageTexts;

  String get fullText => pageTexts.join('\n\n');

  /// The sidecar encoding (§R6.1: extraction runs once). JSON so
  /// page boundaries survive — the reader rebuilds per-page
  /// chunks from it without re-running the PDF engine.
  String encodeSidecar() => jsonEncode({'pages': pageTexts});

  static List<String> decodeSidecar(String content) {
    final decoded = jsonDecode(content);
    if (decoded is! Map) {
      throw const FormatException('sidecar is not a JSON object');
    }
    final pages = decoded['pages'];
    if (pages is! List || pages.any((e) => e is! String)) {
      throw const FormatException('sidecar pages are malformed');
    }
    return pages.cast<String>();
  }
}

/// Decode TXT bytes: UTF-8, BOM stripped. Throws [FormatException]
/// on invalid UTF-8 (the caller maps that to `failed`).
String decodeTxtBytes(List<int> bytes) {
  var body = bytes;
  if (body.length >= 3 &&
      body[0] == 0xEF &&
      body[1] == 0xBB &&
      body[2] == 0xBF) {
    body = body.sublist(3);
  }
  return utf8.decode(body); // strict: throws on malformed input
}

/// Runs extraction for an imported document and classifies the
/// outcome. Never throws for content reasons — a bad document is
/// a status, not a crash (TESTING.md S4 adversarial-import rule).
Future<ExtractionOutcome> extractDocumentText({
  required String kind,
  required String filePath,
  required List<int> bytes,
  required PdfPageTextExtractor pdfExtractor,
}) async {
  if (kind == SourceKind.txt) {
    try {
      final text = decodeTxtBytes(bytes);
      if (text.trim().isEmpty) {
        return const ExtractionOutcome(
            status: ExtractionStatus.failed, pageTexts: []);
      }
      return ExtractionOutcome(
          status: ExtractionStatus.ok, pageTexts: [text]);
    } on FormatException {
      return const ExtractionOutcome(
          status: ExtractionStatus.failed, pageTexts: []);
    }
  }
  if (kind == SourceKind.pdf) {
    try {
      final pages = await pdfExtractor(filePath);
      final nonEmpty =
          pages.where((t) => t.trim().isNotEmpty).length;
      if (nonEmpty == 0) {
        return const ExtractionOutcome(
            status: ExtractionStatus.scannedNoText, pageTexts: []);
      }
      return ExtractionOutcome(
        status: nonEmpty == pages.length
            ? ExtractionStatus.ok
            : ExtractionStatus.partial,
        pageTexts: pages,
      );
    } catch (_) {
      return const ExtractionOutcome(
          status: ExtractionStatus.failed, pageTexts: []);
    }
  }
  // Links, packs, generic files: no in-app text extraction.
  return const ExtractionOutcome(
      status: ExtractionStatus.ok, pageTexts: []);
}

/// Split [text] into reading-card chunks of roughly 120–200
/// words, breaking on blank lines first and on sentences when a
/// single paragraph runs long.
List<ReadingChunk> chunkText(
  String text, {
  int? page,
  int firstIndex = 0,
}) {
  final normalised = text.replaceAll('\r\n', '\n');
  final paragraphs = <({String text, int offset})>[];
  var cursor = 0;
  for (final raw in normalised.split(RegExp(r'\n\s*\n'))) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) continue;
    final at = normalised.indexOf(trimmed, cursor);
    paragraphs.add((text: trimmed, offset: at < 0 ? cursor : at));
    if (at >= 0) cursor = at + trimmed.length;
  }

  final chunks = <ReadingChunk>[];
  var buffer = StringBuffer();
  var bufferOffset = 0;
  var bufferWords = 0;

  void flush() {
    if (bufferWords == 0) return;
    chunks.add(ReadingChunk(
      index: firstIndex + chunks.length,
      text: buffer.toString(),
      page: page,
      startOffset: bufferOffset,
    ));
    buffer = StringBuffer();
    bufferWords = 0;
  }

  void addBlock(String blockText, int blockOffset) {
    final words = _wordCount(blockText);
    if (bufferWords > 0 && bufferWords + words > 200) flush();
    if (bufferWords == 0) bufferOffset = blockOffset;
    if (buffer.isNotEmpty) buffer.write('\n\n');
    buffer.write(blockText);
    bufferWords += words;
  }

  for (final para in paragraphs) {
    if (_wordCount(para.text) <= 220) {
      addBlock(para.text, para.offset);
    } else {
      // Long paragraph: feed it sentence by sentence.
      var searchFrom = 0;
      for (final sentence in splitSentences(para.text)) {
        final at = para.text.indexOf(sentence, searchFrom);
        addBlock(sentence, para.offset + (at < 0 ? searchFrom : at));
        if (at >= 0) searchFrom = at + sentence.length;
      }
    }
  }
  flush();
  return chunks;
}

/// Build the full chunk sequence for a source's extracted pages
/// (TXT: one "page" = the whole text, page numbers null).
List<ReadingChunk> chunksForPages(List<String> pageTexts,
    {required bool paged}) {
  final all = <ReadingChunk>[];
  for (var i = 0; i < pageTexts.length; i++) {
    all.addAll(chunkText(
      pageTexts[i],
      page: paged ? i + 1 : null,
      firstIndex: all.length,
    ));
  }
  return all;
}

/// Split a block of text into sentences (Latin + Arabic
/// terminators). Good enough for picking a sentence to mark —
/// the owner confirms the exact sentence in the UI.
List<String> splitSentences(String text) {
  final out = <String>[];
  final pattern = RegExp(r'[^.!?؟…]+(?:[.!?؟…]+["”’»]*)?');
  for (final m in pattern.allMatches(text)) {
    final s = m.group(0)!.trim();
    if (s.isNotEmpty) out.add(s);
  }
  return out;
}

int _wordCount(String s) =>
    s.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
