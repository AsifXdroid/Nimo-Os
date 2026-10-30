/// CORE — filename hygiene for names that arrive from OUTSIDE the
/// app (share intents, picked files, backup entries).
///
/// Such names are untrusted: they may contain path separators
/// (both `/` and `\`), traversal segments, control characters, or
/// absurd lengths. [sanitizeFileName] reduces any of them to one
/// safe path segment. It is a *name* rule only — containment in a
/// directory is enforced separately by the stores that write.
library;

import 'package:path/path.dart' as p;

/// Reduce [name] to a single safe filename: keep only the final
/// path segment, whitelist characters, strip leading dots, cap
/// the length at 100 chars (extension preserved). Never returns
/// an empty or dot-only name.
String sanitizeFileName(String name) {
  var base = name.split(RegExp(r'[/\\]')).last.trim();
  base = base.replaceAll(RegExp(r'[^A-Za-z0-9._\- ]'), '_');
  base = base.replaceAll(RegExp(r'\s+'), '_');
  base = base.replaceAll(RegExp(r'^\.+'), '');
  base = base.replaceAll(RegExp(r'_+'), '_');
  if (base.isEmpty || base == '.' || base == '..') base = 'file';
  if (base.length > 100) {
    final ext = p.extension(base);
    final keep = 100 - ext.length;
    base = keep > 0 ? base.substring(0, keep) + ext : base.substring(0, 100);
  }
  return base;
}
