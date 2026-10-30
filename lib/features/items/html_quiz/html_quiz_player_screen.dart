/// HTML quiz — legacy player (S5, §R10.2).
///
/// Plays a self-contained HTML quiz stored in the Library
/// `html_quizzes/` folder in a hardened Android WebView.
/// Linux/desktop has no stable WebView for this route (§R8.4),
/// so on desktop (S7) the quiz opens in the system browser via a
/// `file:` URL — the §R8.4 fallback. Other non-Android platforms
/// keep the plain message.
///
/// Hardening (§7 PLATFORM row, TESTING.md §9 S5): JavaScript
/// is on only because quizzes need it; file access from file
/// URLs and universal access are off; windows cannot open
/// automatically; zoom is off; and every navigation is decided
/// by [quizNavigationAllowed] — anything outside the quiz's
/// own folder is cancelled and reported.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../../learn/library_store.dart';
import 'html_quiz_policy.dart';

class HtmlQuizPlayerScreen extends StatelessWidget {
  const HtmlQuizPlayerScreen({
    super.key,
    required this.library,
    required this.payload,
    required this.title,
  });

  final LibraryStore library;

  /// Item payload; `file_rel_path` is the Library-relative path
  /// of the quiz HTML file (see items_screen creation flow).
  final Map<String, Object?> payload;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: _body(context),
    );
  }

  Widget _body(BuildContext context) {
    final relRaw = payload['file_rel_path'];
    final rel = relRaw is String ? relRaw : null;
    if (rel == null || rel.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('This quiz has no file attached.'),
        ),
      );
    }

    final File file;
    try {
      file = library.resolve(rel);
    } catch (_) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('This quiz file could not be found.'),
        ),
      );
    }

    // Existence check is synchronous on purpose: a vanished file
    // must degrade to a plain message, never a WebView error
    // page or a crash. Quiz files are small and local.
    if (!file.existsSync()) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('This quiz file could not be found.'),
        ),
      );
    }

    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      // Desktop fallback (§R8.4, S7): no stable WebView — hand
      // the file to the system browser. The quiz is the owner's
      // own local file from their Library; the browser is outside
      // the app's hardening boundary, which the copy says plainly.
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'On desktop, HTML quizzes open in your browser.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => launchUrl(
                  Uri.file(file.path),
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.open_in_browser),
                label: const Text('Open in browser'),
              ),
            ],
          ),
        ),
      );
    }

    if (!Platform.isAndroid) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('HTML quizzes play in the Android app.'),
        ),
      );
    }

    final quizFilePath = file.path;
    final initialUrl = URLRequest(url: WebUri(Uri.file(quizFilePath).toString()));

    return InAppWebView(
      initialUrlRequest: initialUrl,
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        allowFileAccessFromFileURLs: false,
        allowUniversalAccessFromFileURLs: false,
        useShouldOverrideUrlLoading: true,
        javaScriptCanOpenWindowsAutomatically: false,
        supportZoom: false,
      ),
      shouldOverrideUrlLoading: (controller, navigationAction) async {
        final url = navigationAction.request.url?.toString() ?? '';
        // The quiz's own folder may use plain relative names in
        // markup; the WebView reports them resolved, but keep the
        // file-name check honest for the raw string too.
        final allowed = quizNavigationAllowed(
          url,
          quizFilePath: quizFilePath,
        );
        if (!allowed) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('External links are blocked inside quizzes.'),
              ),
            );
          }
          return NavigationActionPolicy.CANCEL;
        }
        return NavigationActionPolicy.ALLOW;
      },
    );
  }
}

/// The display name for a quiz payload (file base name), used by
/// the detail screen. Type-tolerant like other payload reads.
String htmlQuizFileName(Map<String, Object?>? payload) {
  final raw = payload?['file_rel_path'];
  if (raw is! String || raw.isEmpty) return '';
  return p.basename(raw);
}
