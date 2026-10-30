/// LEARN — the PDF viewer (§R8.3): pdfrx (PDFium) rendering the
/// original file from the Library. Nimo never edits the PDF —
/// marked points are our own records (reading_screen.dart).
///
/// The viewer's menus come from pdfrx's `material_ui` layer; the
/// package ships a localization fallback, so it renders inside
/// our Material app with just the background colour themed to
/// the Midnight plate here.
library;

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import 'learn_services.dart';
import 'learn_store.dart';
import 'reading_screen.dart';

class PdfSourceScreen extends StatelessWidget {
  const PdfSourceScreen({
    super.key,
    required this.learn,
    required this.source,
  });

  final LearnServices learn;
  final Source source;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rel = source.fileRelPath;
    final file = rel == null ? null : learn.library.resolve(rel);
    return Scaffold(
      appBar: AppBar(
        title: Text(source.title),
        actions: [
          if (source.hasReadableText)
            IconButton(
              icon: const Icon(Icons.style_outlined),
              tooltip: 'Read as cards',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      ReadingScreen(learn: learn, source: source),
                ),
              ),
            ),
        ],
      ),
      body: file == null || !file.existsSync()
          ? const Center(
              child: Text('The PDF file is missing from the Library.'))
          : PdfViewer.file(
              file.path,
              params: PdfViewerParams(
                backgroundColor: scheme.surfaceContainerLowest,
                pageDropShadow: const BoxShadow(
                  color: Colors.black54,
                  blurRadius: 4,
                  spreadRadius: 2,
                  offset: Offset(2, 2),
                ),
              ),
            ),
    );
  }
}
