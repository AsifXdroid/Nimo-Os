/// CORE — hybrid logical clock stamps for sync identity (§R6.3).
///
/// The stamp state (`wallMs:counter`) persists in `sync_meta` so
/// monotonicity survives restarts; stamps are formatted by
/// [formatHlc] in ids.dart. Used by the S4+ stores when they mint
/// `updated_hlc` values. ReviewStore (S3) keeps its own private
/// copy of this logic from before this helper existed; both write
/// the same `sync_meta` key, so stamps stay mutually monotonic.
/// Unifying them is an S7 tidy-up, not an S4 behaviour change.
library;

import 'package:sqflite/sqflite.dart';

import 'db/app_database.dart';
import 'ids.dart';

/// Returns the next HLC stamp for this device, strictly greater
/// than every stamp this device has issued before. The
/// read-modify-write runs inside a transaction: two interleaved
/// callers must never mint the same stamp (§R6.3 invariant).
Future<String> nextHlc(Database db, {DateTime? at}) async {
  final deviceId = await AppDatabase.deviceId(db);
  return db.transaction((txn) async {
    final rows = await txn.query(
      'sync_meta',
      where: 'key = ?',
      whereArgs: ['hlc_state'],
      limit: 1,
    );
    var lastWall = -1;
    var lastCounter = -1;
    if (rows.isNotEmpty) {
      final parts = (rows.first['value']! as String).split(':');
      lastWall = int.parse(parts[0]);
      lastCounter = int.parse(parts[1]);
    }
    final nowMs = (at ?? DateTime.now()).millisecondsSinceEpoch;
    final wall = nowMs > lastWall ? nowMs : lastWall;
    final counter = wall == lastWall ? lastCounter + 1 : 0;
    await txn.insert('sync_meta', {
      'key': 'hlc_state',
      'value': '$wall:$counter',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return formatHlc(wall, counter, deviceId);
  });
}
