import '../learn/library_store.dart';
import '../store.dart';

/// Deletes [item]; additionally removes its Library audio file under the guards.
Future<void> deleteItemWithFileCleanup({
  required Store store,
  required LibraryStore? library,
  required Item item,
}) async {
  Object? rawRel;
  if (item.type == 'audio') {
    final payload = item.payload;
    if (payload != null) rawRel = payload['file_rel_path'];
  }
  await store.deleteItem(item.id);
  if (library == null) return;
  if (rawRel is! String) return;
  final rel = rawRel;
  if (rel.startsWith('audio/') == false) return;
  if (rel.contains('..')) return;
  try {
    final refs = await store.audioFileReferenceCount(rel);
    if (refs > 0) return;
    final file = library.resolve(rel);
    if (await file.exists() == false) return;
    // Strict canonical check for a DESTRUCTIVE operation
    // (Phase 8 review): LibraryStore.resolve() deliberately
    // falls back to a lexical check when canonicalisation
    // fails; deletion must not. If canonicalising the root
    // or the target throws, or the canonical target escapes
    // the canonical root (a symlink hop), the file stays.
    final rootCanon = await library.root.resolveSymbolicLinks();
    final fileCanon = await file.resolveSymbolicLinks();
    if (fileCanon.startsWith(rootCanon) == false) return;
    await file.delete();
  } catch (_) {
    // Keep the file.
  }
}
