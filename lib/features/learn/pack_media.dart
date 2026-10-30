/// LEARN engine — resolving a question's image from the Library
/// (S5 step C2a).
///
/// An image_point question's payload names a MEDIA ID, not a
/// file. The file lives at PackImporter's deterministic path for
/// the question's pack — but the declared mime (which picks the
/// extension) is a property of the importing pack, not of the
/// question, so resolution PROBES the supported image mimes in
/// order and returns the first file that actually exists.
library;

import 'dart:io';

import 'learn_engine_store.dart';
import 'library_store.dart';
import 'pack_importer.dart';

/// Mimes probed, in order, when resolving a question image.
const List<String> _probeMimes = [
  'image/png',
  'image/jpeg',
  'image/webp',
  'image/gif',
];

/// Resolve [question]'s image to a Library file, or null when
/// the question is not an image_point, has no pack, names no
/// media id, or no probed media file exists in the Library.
Future<File?> resolveQuestionImage(
  LibraryStore library,
  LearnQuestion question,
) async {
  if (question.type != 'image_point') return null;
  final packId = question.packId;
  if (packId == null) return null;
  final image = question.payload['image'];
  if (image is! String || image.isEmpty) return null;
  for (final mime in _probeMimes) {
    final rel = PackImporter.mediaRelPath(packId, image, mime);
    if (await library.exists(rel)) return library.resolve(rel);
  }
  return null;
}
