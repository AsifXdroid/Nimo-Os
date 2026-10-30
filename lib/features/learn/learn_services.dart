/// LEARN — the bundle of learn-data services screens receive
/// together (store + library + importer are always used as a set;
/// passing them as one object keeps screen constructors readable).
///
/// S5 adds the engine side: [engine] (questions / sessions /
/// packs over schema v5) and [packImporter], both built over the
/// SAME database — and the importer is built over the SAME
/// [engine] instance the screens use, so there is exactly one
/// engine store per app run.
library;

import 'package:sqflite/sqflite.dart';

import 'import_service.dart';
import 'learn_engine_store.dart';
import 'learn_store.dart';
import 'library_store.dart';
import 'pack_importer.dart';

class LearnServices {
  LearnServices(this.store, this.library, {required this.db})
      : imports = ImportService(store, library);

  final LearnStore store;
  final LibraryStore library;
  final ImportService imports;

  /// The database every S5 engine service is built over.
  final Database db;

  /// The S5 engine store (questions, review log, sessions, packs).
  late final LearnEngineStore engine = LearnEngineStore(db);

  /// The quiz-pack importer, over THIS bundle's [engine] instance.
  late final PackImporter packImporter =
      PackImporter(engine, store, library);
}
