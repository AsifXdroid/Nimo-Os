/// HTML quiz — pure navigation policy for the legacy player.
///
/// A quiz may only navigate inside its own Library folder: the
/// quiz file itself, or any file inside the same directory as
/// the quiz file (the `html_quizzes/` directory — relative
/// assets a quiz legitimately loads, including assets in
/// subfolders of that directory). Everything else — http,
/// https, data, javascript, about, and `file://` URLs pointing
/// anywhere outside that directory — is blocked.
///
/// Pure: no I/O, no platform checks, so it is unit-testable on
/// the host.
library;

import 'package:path/path.dart' as p;

/// Whether [url] may load when the quiz file is [quizFilePath].
///
/// [quizFilePath] is the quiz file's absolute filesystem path
/// (as produced by `LibraryStore.resolve(...).path`); a
/// `file://` URL for the quiz file is also accepted, defensively.
/// [url] is the raw navigation URL from the WebView — it is
/// treated as untrusted: scheme and host are checked
/// case-insensitively, percent-encoding is decoded before the
/// path comparison, and the decoded path is normalised so
/// encoded or plain `..` traversal cannot escape.
bool quizNavigationAllowed(String url, {required String quizFilePath}) {
  final raw = url.trim();
  if (raw.isEmpty || quizFilePath.trim().isEmpty) return false;

  final uri = Uri.tryParse(raw);
  if (uri == null) return false;
  if (uri.scheme.toLowerCase() != 'file') return false;

  // file:// URLs with a remote host are not local files.
  final host = uri.host.toLowerCase();
  if (host.isNotEmpty && host != 'localhost') return false;

  final String candidatePath;
  try {
    candidatePath = uri.toFilePath();
  } catch (_) {
    return false;
  }
  if (candidatePath.isEmpty) return false;

  final quizPath = _quizFileSystemPath(quizFilePath);
  if (quizPath == null || quizPath.isEmpty) return false;

  final candidate = p.normalize(candidatePath);
  final quiz = p.normalize(quizPath);
  if (candidate == quiz) return true;

  final quizDir = p.dirname(quiz);
  return p.isWithin(quizDir, candidate);
}

/// Resolve [quizFilePath] to a plain filesystem path, accepting
/// either a plain path or a `file://` URL.
String? _quizFileSystemPath(String quizFilePath) {
  final trimmed = quizFilePath.trim();
  // Detect a file:// URL case-insensitively without relying on
  // Uri normalisation for the stored value.
  if (trimmed.length >= 7 &&
      trimmed.substring(0, 7).toLowerCase() == 'file://') {
    try {
      final uri = Uri.tryParse(trimmed);
      if (uri == null) return null;
      return uri.toFilePath();
    } catch (_) {
      return null;
    }
  }
  return trimmed;
}
