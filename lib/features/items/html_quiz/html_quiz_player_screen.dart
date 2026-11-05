/// HTML player (S5, §R10.2 / D-049).
///
/// Plays a self-contained HTML file stored in the Library
/// `html_quizzes/` folder in a hardened Android WebView.
///
/// D-049 rename: the item type is now called "HTML" (any HTML file),
/// not "HTML quiz". The folder name (html_quizzes/) and DB key
/// (html_quiz) are kept for backward compatibility — no migration.
///
/// Android hardening:
///   • allowFileAccess: true  — lets the WebView open the local
///     file:// URL that we hand it. Without this modern Android
///     (API 29+) blocks the initial load and shows a blank page.
///   • allowFileAccessFromFileURLs: true  — lets HTML/JS inside
///     the file itself read sibling assets (CSS, images, scripts)
///     via relative paths. Restricted to the quiz's own folder by
///     [quizNavigationAllowed].
///   • allowUniversalAccessFromFileURLs: false — still blocked, so
///     the file cannot reach arbitrary file:// paths.
///   • JavaScript on — required by most interactive HTML content.
///   • All other outbound navigation (http/https, other folders)
///     cancelled by [shouldOverrideUrlLoading].
///
/// Linux/desktop has no stable in-process WebView (§R8.4, S7):
/// the file opens in the system browser instead. Other non-Android
/// platforms show a plain message.
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
    this.showAppBar = true,
  });

  final LibraryStore library;
  final Map<String, Object?> payload;
  final String title;
  final bool showAppBar;

  @override
  Widget build(BuildContext context) {
    if (!showAppBar) {
      return _body(context);
    }
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
          child: Text('This HTML file has no file attached.'),
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
          child: Text('This HTML file could not be found.'),
        ),
      );
    }

    // Existence check is synchronous: a vanished file must degrade
    // to a plain message, never a WebView error page or a crash.
    if (!file.existsSync()) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('This HTML file could not be found.'),
        ),
      );
    }

    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      // Desktop fallback (§R8.4, S7): no stable in-process WebView.
      // Hand the file to the system browser. The file is the owner's
      // own local content; the browser is outside the app's hardening
      // boundary, which the message states plainly.
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'On desktop, HTML files open in your browser.',
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
          child: Text('HTML files play in the Android app.'),
        ),
      );
    }

    final filePath = file.path;
    final initialUrl = URLRequest(
        url: WebUri(Uri.file(filePath).toString()));

    return InAppWebView(
      initialUrlRequest: initialUrl,
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        // D-049 fix: allowFileAccess must be true so Android (API 29+)
        // permits the initial file:// load. Without it the WebView
        // silently shows a blank page on modern Android builds.
        allowFileAccess: true,
        // Allow the HTML itself to load relative sibling assets (CSS,
        // images, JS) from its own directory via file:// URLs.
        // Cross-directory access is still blocked by the nav policy.
        allowFileAccessFromFileURLs: true,
        // Still off: the file must not be able to read arbitrary
        // file:// paths outside its own folder.
        allowUniversalAccessFromFileURLs: false,
        useShouldOverrideUrlLoading: true,
        javaScriptCanOpenWindowsAutomatically: false,
        supportZoom: false,
      ),
      shouldOverrideUrlLoading: (controller, navigationAction) async {
        final url = navigationAction.request.url?.toString() ?? '';
        // The file's own folder may use plain relative names in
        // markup; the WebView reports them resolved. Block anything
        // that leaves the file's own folder.
        final allowed = quizNavigationAllowed(
          url,
          quizFilePath: filePath,
        );
        if (!allowed) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('External links are blocked in HTML files.'),
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

/// The display name for an HTML payload (file base name), used by
/// the detail screen. Type-tolerant like other payload reads.
String htmlQuizFileName(Map<String, Object?>? payload) {
  final raw = payload?['file_rel_path'];
  if (raw is! String || raw.isEmpty) return '';
  return p.basename(raw);
}
