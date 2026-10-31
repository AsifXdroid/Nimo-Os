/// SYNC — Stage A "Sync now" data packages (§R7.2, S7).
///
/// The owner's model: the Library folder travels by a folder-sync
/// tool (Syncthing-Fork, see docs/SYNC_SETUP.md); DATA travels in
/// explicit packages the owner exports/imports by hand. The live
/// SQLite file is NEVER synced (§R7 hard rule).
///
/// **How change is detected without an op-writing retrofit:** the
/// S3 scaffold gave every syncable row a `sync_id` + `updated_hlc`,
/// but only the S4/S5 stores stamp mutations, and NO store writes
/// the `sync_ops` log. So this engine diffs row STATE: export
/// canonicalises every syncable row (foreign keys translated to
/// parent `sync_id`s — local integer ids are meaningless on the
/// other device), hashes it, and compares against `sync_base`,
/// the last-synced state. Differences become the package's ops;
/// rows that vanished become delete ops. Import is a 3-way merge
/// (base / local / remote), which is what makes conflict
/// detection — and therefore conflict COPIES instead of silent
/// loss (§R7.2) — possible at all.
///
/// Merge rules (per §R7.2, as corrected by the red team):
/// - Append-only tables (review_log, learn_sessions): union by
///   sync_id. Same-id divergence is impossible in practice; if it
///   ever happened, both versions survive (local row + a conflict
///   copy of the remote payload).
/// - `day_reviews` / `day_plans` merge by their natural key (the
///   date), never by sync_id alone. Day reviews: scores LWW by
///   HLC; a non-null major point is never erased by a null one;
///   two different points → the loser's text is a conflict copy.
///   `is_counted` is NOT in the payload — it is derived locally
///   (red-team #17); import re-runs the streak fold.
/// - Day-plan items merge within their date; routine items carry
///   deterministic sync_ids (template sync_id + date, TodayStore)
///   so both devices generating the same morning dedupe. A pure
///   `done`-toggle divergence merges LWW by HLC with NO conflict
///   copy — a toggle's last action is the intent (§R7.2).
/// - Every other both-sides-changed row: last-writer-wins by HLC
///   for the live row, and the LOSING payload is preserved as a
///   `sync_conflicts` row. Conflict rows themselves sync
///   (append-only), so the copy is visible on both devices after
///   the next exchange.
/// - Deletes are tombstone ops synthesised from the base diff.
///   Delete-vs-edit keeps the edited row unless the delete's HLC
///   is later, and either way the losing side is a conflict copy.
/// - Derived data NEVER syncs: `streak_state` and `shield_events`
///   are fold materialisations (S3 NOTE N1) and re-derive on the
///   importing device via ReviewStore.evaluate.
///
/// Safety rails:
/// - **Quarantine (red-team #7):** an op whose HLC wall time is
///   more than 1 day in the future, or a day-keyed record dated
///   more than 1 day ahead, is HELD in `sync_quarantine` —
///   reported, never applied. Fixing the clock and re-importing
///   the same package re-evaluates it (quarantined ops are not
///   marked seen).
/// - **Receiver clamping (quality-pass §R7):** HLC only tolerates
///   small skew. Import advances this device's HLC state by the
///   newest stamp SEEN clamped to local wall time, so a peer's
///   fast clock can never poison this device's future stamps.
/// - **Atomicity:** a package that fails any check (bad zip,
///   manifest mismatch, ops digest mismatch, malformed op)
///   applies NOTHING. All merges run in one transaction.
///   Idempotence: applied op_ids are recorded in `sync_ops`;
///   re-importing a package is a pure no-op.
/// - **Repair** is NOT here: snapshot restore goes through
///   BackupStore with the D-011 guards (see SyncSection).
///
/// Known limits, honestly stated: with exactly two devices the
/// single `sync_base` IS the per-peer base; a third device would
/// need per-peer bases. For rows in tables whose stores do not
/// stamp `updated_hlc` at edit time (S1/S2 stores), the op stamp
/// is minted at EXPORT time, so LWW between two offline edits is
/// decided by export order — the conflict copy is what guarantees
/// nothing is silently lost in that case.
library;

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../core/db/app_database.dart';
import '../../core/hlc.dart';
import '../../core/ids.dart';
import '../learn/library_store.dart';
import '../review/review_store.dart';
import '../today/today_store.dart';

class SyncException implements Exception {
  SyncException(this.message);
  final String message;
  @override
  String toString() => message;
}

// ------------------------------------------------------------ format

class SyncManifest {
  const SyncManifest({
    required this.formatVersion,
    required this.deviceId,
    required this.exportSeq,
    required this.createdAt,
    required this.full,
    required this.opCount,
    required this.opsSha256,
  });

  final int formatVersion;
  final String deviceId;
  final int exportSeq;
  final int createdAt;
  final bool full;
  final int opCount;
  final String opsSha256;

  Map<String, Object?> toJson() => {
    'kind': 'nimo-sync',
    'format_version': formatVersion,
    'device_id': deviceId,
    'export_seq': exportSeq,
    'created_at': createdAt,
    'full': full,
    'op_count': opCount,
    'ops_sha256': opsSha256,
  };

  factory SyncManifest.fromJson(Map<String, Object?> json) {
    if (json['kind'] != 'nimo-sync') {
      throw SyncException('That file is not a Nimo sync package.');
    }
    return SyncManifest(
      formatVersion: json['format_version']! as int,
      deviceId: json['device_id']! as String,
      exportSeq: json['export_seq']! as int,
      createdAt: json['created_at']! as int,
      full: json['full']! as bool,
      opCount: json['op_count']! as int,
      opsSha256: json['ops_sha256']! as String,
    );
  }
}

class SyncOp {
  const SyncOp({
    required this.opId,
    required this.entity,
    required this.syncId,
    required this.op,
    required this.hlc,
    this.fields,
  });

  final String opId;
  final String entity;
  final String syncId;

  /// 'upsert' or 'delete'.
  final String op;
  final String hlc;

  /// Canonical payload for upserts (FKs as `<column>_sync`).
  final Map<String, Object?>? fields;

  Map<String, Object?> toJson() => {
    'op_id': opId,
    'entity': entity,
    'sync_id': syncId,
    'op': op,
    'hlc': hlc,
    if (fields != null) 'fields': fields,
  };

  factory SyncOp.fromJson(Map<String, Object?> json) {
    final opId = json['op_id'];
    final entity = json['entity'];
    final syncId = json['sync_id'];
    final op = json['op'];
    final hlc = json['hlc'];
    if (opId is! String ||
        entity is! String ||
        syncId is! String ||
        op is! String ||
        (op != 'upsert' && op != 'delete') ||
        hlc is! String) {
      throw SyncException('Sync package contains a malformed op.');
    }
    // S7 review S5: an unvalidated stamp bypasses the quarantine
    // clock check (unparseable reads as wall -1) AND wins every
    // LWW comparison lexicographically ('zzz…' beats any real
    // stamp). Only the fixed-width formatHlc shape is a stamp.
    if (!RegExp(r'^\d{13,}-\d{6,}-').hasMatch(hlc)) {
      throw SyncException('Sync package contains a malformed timestamp.');
    }
    final rawFields = json['fields'];
    if (op == 'upsert' && rawFields is! Map) {
      throw SyncException('Sync package contains a malformed op.');
    }
    return SyncOp(
      opId: opId,
      entity: entity,
      syncId: syncId,
      op: op,
      hlc: hlc,
      fields: rawFields is Map ? rawFields.cast<String, Object?>() : null,
    );
  }
}

class SyncExportResult {
  const SyncExportResult({
    required this.file,
    required this.opCount,
    required this.exportSeq,
  });

  /// Null when there was nothing new to send.
  final File? file;
  final int opCount;
  final int exportSeq;
}

class SyncImportReport {
  int applied = 0;
  int duplicates = 0;
  int keptLocal = 0;
  int conflicts = 0;
  int quarantined = 0;
  int alreadyQuarantined = 0;
  int stale = 0;
  final List<String> failedFiles = [];
  bool streakReevaluated = false;

  bool get isEmpty => applied == 0 && conflicts == 0 && quarantined == 0;

  String describe() {
    final parts = <String>[
      if (applied > 0) '$applied change${applied == 1 ? '' : 's'} applied',
      if (keptLocal > 0) '$keptLocal kept from this device',
      if (duplicates > 0) '$duplicates already seen',
      if (conflicts > 0)
        '$conflicts conflict cop${conflicts == 1 ? 'y' : 'ies'} kept',
      if (quarantined > 0) '$quarantined held (future-dated)',
      if (alreadyQuarantined > 0)
        '$alreadyQuarantined still held (future-dated)',
      if (stale > 0)
        '$stale outdated change${stale == 1 ? '' : 's'} ignored '
            '(already superseded)',
      if (failedFiles.isNotEmpty)
        '${failedFiles.length} file(s) could not be imported: '
            '${failedFiles.join(', ')}',
    ];
    return parts.isEmpty ? 'Nothing new in that package.' : parts.join(', ');
  }
}

class SyncConflict {
  const SyncConflict({
    required this.id,
    required this.entity,
    required this.rowSyncId,
    required this.kind,
    required this.keptText,
    required this.lostText,
    required this.createdAt,
  });

  final int id;
  final String entity;
  final String rowSyncId;
  final String kind;
  final String? keptText;
  final String? lostText;
  final int createdAt;

  factory SyncConflict.fromRow(Map<String, Object?> r) => SyncConflict(
    id: r['id'] as int,
    entity: r['entity'] as String,
    rowSyncId: r['row_sync_id'] as String,
    kind: r['kind'] as String,
    keptText: r['kept_text'] as String?,
    lostText: r['lost_text'] as String?,
    createdAt: r['created_at'] as int,
  );
}

class SyncPeerStatus {
  const SyncPeerStatus({
    required this.deviceId,
    this.lastImportHlc,
    this.lastImportAt,
  });

  final String deviceId;
  final String? lastImportHlc;
  final int? lastImportAt;
}

class SyncStatus {
  const SyncStatus({
    required this.deviceId,
    required this.lastExportAt,
    required this.lastExportFile,
    required this.peers,
    required this.conflictCount,
    required this.quarantineCount,
  });

  final String deviceId;
  final int? lastExportAt;
  final String? lastExportFile;
  final List<SyncPeerStatus> peers;
  final int conflictCount;
  final int quarantineCount;
}

// ------------------------------------------------------------ entity specs

class _Fk {
  const _Fk(this.column, this.parent);
  final String column;
  final String parent;
}

class _Spec {
  const _Spec(
    this.fields, {
    this.fks = const [],
    this.naturalKey,
    this.appendOnly = false,
  });

  /// Plain columns carried in the payload, in canonical order.
  final List<String> fields;

  /// FK columns, carried as `<column>_sync` (parent sync_ids).
  final List<_Fk> fks;

  /// Natural-key column ('date') for day_plans / day_reviews.
  final String? naturalKey;
  final bool appendOnly;
}

/// Every entity that travels in a sync package, PARENTS FIRST
/// (import applies upserts in this order). Deliberately absent:
/// streak_state + shield_events (derived — re-derived locally),
/// app_settings (device-local), sync machinery itself.
const List<String> syncEntityOrder = [
  'workspaces',
  // D-042: projects/items move ahead of plan_templates —
  // a template may link an item, and import stays
  // parents-first so the link resolves in the same pass.
  'projects',
  'items',
  'plan_templates',
  'goals',
  'day_plans',
  'topics',
  'checklist_entries',
  'day_plan_items',
  'sources',
  'packs',
  'questions',
  'marked_points',
  'learn_sessions',
  'review_log',
  'day_reviews',
  'sync_conflicts',
];

final Map<String, _Spec> _specs = {
  'workspaces': const _Spec([
    'name',
    'sort_order',
    'created_at',
    'updated_at',
    'pinned',
  ]),
  'plan_templates': const _Spec(
    [
      'title',
      'position',
      'is_active',
      'created_at',
      'starter_title',
      'anchor_text',
      'track',
      'counts_core',
      // D-042: schedule mask + bare URL are plain fields; the
      // item link travels as item_id_sync (parent sync_id),
      // never as a local integer.
      'weekdays',
      'url',
    ],
    fks: [_Fk('item_id', 'items')],
  ),
  'goals': const _Spec([
    'title',
    'target',
    'current',
    'unit',
    'position',
    'created_at',
    'track',
  ]),
  // created_at is deliberately NOT a synced field: two
  // devices generating the same morning would "conflict"
  // over a bookkeeping timestamp. It is materialised
  // locally on import instead (see _rowFromPayload).
  'day_plans': const _Spec(['date'], naturalKey: 'date'),
  'topics': const _Spec(
    ['title', 'trigger_url', 'status', 'track', 'created_at', 'updated_at'],
    fks: [_Fk('project_id', 'projects')],
  ),
  'projects': const _Spec(
    ['name', 'sort_order', 'created_at', 'updated_at'],
    fks: [_Fk('workspace_id', 'workspaces')],
  ),
  'items': const _Spec(
    [
      'type',
      'title',
      'note',
      'payload',
      'sort_order',
      'created_at',
      'updated_at',
    ],
    fks: [_Fk('project_id', 'projects')],
  ),
  'checklist_entries': const _Spec(
    ['text', 'is_done', 'sort_order'],
    fks: [_Fk('item_id', 'items')],
  ),
  'day_plan_items': const _Spec(
    ['title', 'kind', 'done', 'carried', 'position', 'counts_core', 'url'],
    fks: [
      _Fk('day_plan_id', 'day_plans'),
      _Fk('template_id', 'plan_templates'),
      // D-042: the linked resource, carried as item_id_sync.
      _Fk('item_id', 'items'),
    ],
  ),
  'sources': const _Spec(
    [
      'kind',
      'title',
      'file_rel_path',
      'url',
      'text_rel_path',
      'extraction_status',
      'created_at',
    ],
    fks: [_Fk('topic_id', 'topics')],
  ),
  'packs': const _Spec(
    [
      'pack_id',
      'version',
      'title',
      'language',
      'arc',
      'question_count',
      'imported_at',
      'updated_at',
    ],
    fks: [_Fk('topic_id', 'topics'), _Fk('source_id', 'sources')],
  ),
  'questions': const _Spec(
    [
      'pack_id',
      'pack_qid',
      'type',
      'payload',
      'difficulty',
      'ef',
      'reps',
      'lapses',
      'interval_days',
      'due_at',
      'suspended',
      'created_at',
      'updated_at',
    ],
    fks: [_Fk('topic_id', 'topics'), _Fk('source_id', 'sources')],
  ),
  'marked_points': const _Spec(
    [
      'sentence',
      'span_text',
      'page',
      'char_offset',
      'chunk_index',
      'created_at',
    ],
    fks: [
      _Fk('source_id', 'sources'),
      _Fk('topic_id', 'topics'),
      _Fk('question_id', 'questions'),
    ],
  ),
  'learn_sessions': const _Spec(
    [
      'started_at',
      'ended_at',
      'finished',
      'kind',
      'pack_id',
      'cards_total',
      'cards_correct',
      'enjoyment',
      'enjoyment_reason',
      'format_mix',
    ],
    fks: [_Fk('topic_id', 'topics')],
    appendOnly: true,
  ),
  // review_log carries two extra payload keys beyond [_Spec.fields]:
  // `question_id_sync` IS `question_key` (the question's sync_id,
  // snapshotted by S5), and `session_id_sync` resolves the local
  // session id. Both are handled specially in payload build/apply.
  'review_log': const _Spec([
    'question_key',
    'reviewed_at',
    'correct',
    'latency_ms',
  ], appendOnly: true),
  // day_plans carries ONLY its date: created_at is per-device
  // bookkeeping (both devices legitimately create the row at
  // different times), and syncing it would manufacture a
  // both-changed conflict for every shared morning.
  // is_counted is deliberately NOT a field: it is a fold cache
  // (red-team #17) and re-derives on the importing device.
  'day_reviews': const _Spec(
    [
      'date',
      'major_point',
      'self_score',
      'self_note',
      'done_score',
      'score_formula_version',
      'closed_at',
      'tz_offset',
    ],
    fks: [_Fk('major_point_topic_id', 'topics')],
    naturalKey: 'date',
  ),
  'sync_conflicts': const _Spec([
    'entity',
    'row_sync_id',
    'kind',
    'field',
    'kept_text',
    'lost_text',
    'created_at',
  ], appendOnly: true),
};

// ------------------------------------------------------------ the store

class SyncStore {
  SyncStore(this._db);

  final Database _db;

  /// The database this store merges into (S8: the LAN export
  /// guard snapshots bookkeeping on the same handle).
  Database get database => _db;

  static const int formatVersion = 1;

  /// Quarantine horizon (red-team #7): stamps/dates more than
  /// this far in the future are held, not applied.
  static const Duration futureHorizon = Duration(days: 1);

  /// Package defences — generous for a personal op log, far below
  /// anything that could hurt.
  static const int maxZipBytes = 64 * 1024 * 1024;
  static const int maxOpsBytes = 64 * 1024 * 1024;

  static const String _deletedHash = 'sha256:deleted';

  // ---------------------------------------------------------- payloads

  String _hash(Map<String, Object?> payload) =>
      sha256.convert(utf8.encode(jsonEncode(payload))).toString();

  /// Canonical payload for a local row: plain fields verbatim,
  /// each FK replaced by the parent's sync_id under
  /// `<column>_sync`. Used identically for export and for hashing
  /// local state during import merges, so both sides compare
  /// like with like.
  Future<Map<String, Object?>> _payloadOf(
    DatabaseExecutor db,
    String entity,
    Map<String, Object?> row,
  ) async {
    final spec = _specs[entity]!;
    final payload = <String, Object?>{};
    for (final f in spec.fields) {
      payload[f] = row[f];
    }
    for (final fk in spec.fks) {
      final localId = row[fk.column] as int?;
      if (localId == null) {
        payload['${fk.column}_sync'] = null;
      } else {
        final parent = await db.query(
          fk.parent,
          columns: ['sync_id'],
          where: 'id = ?',
          whereArgs: [localId],
          limit: 1,
        );
        payload['${fk.column}_sync'] = parent.isEmpty
            ? null
            : parent.single['sync_id'];
      }
    }
    if (entity == 'review_log') {
      final sessionId = row['session_id'] as int?;
      if (sessionId == null) {
        payload['session_id_sync'] = null;
      } else {
        final s = await db.query(
          'learn_sessions',
          columns: ['sync_id'],
          where: 'id = ?',
          whereArgs: [sessionId],
          limit: 1,
        );
        payload['session_id_sync'] = s.isEmpty ? null : s.single['sync_id'];
      }
    }
    return payload;
  }

  // ---------------------------------------------------------- export

  /// Build a sync package of everything that changed since the
  /// last export (or ALL state when [full] — first pairing), and
  /// write it into `Library/sync/` via the Library's
  /// temp-then-rename rule (sync tools must never see a
  /// half-written package). Returns a null file when there is
  /// nothing new.
  Future<SyncExportResult> exportPackage({
    required Directory libraryRoot,
    bool full = false,
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    await AppDatabase.ensureSyncIdentity(_db);
    final device = await AppDatabase.deviceId(_db);

    // Snapshot current state + base (reads only).
    final current = <String, Map<String, Map<String, Object?>>>{};
    final currentHash = <String, Map<String, String>>{};
    final currentRowId = <String, Map<String, int>>{};
    final currentStamp = <String, Map<String, String?>>{};
    for (final entity in syncEntityOrder) {
      final rows = await _db.query(entity);
      final bySync = <String, Map<String, Object?>>{};
      final hashes = <String, String>{};
      final ids = <String, int>{};
      final stamps = <String, String?>{};
      for (final row in rows) {
        final syncId = row['sync_id'] as String?;
        if (syncId == null) continue;
        if (row['deleted_at_hlc'] != null) continue; // tombstoned
        final payload = await _payloadOf(_db, entity, row);
        bySync[syncId] = payload;
        hashes[syncId] = _hash(payload);
        ids[syncId] = row['id'] as int;
        stamps[syncId] = row['updated_hlc'] as String?;
      }
      current[entity] = bySync;
      currentHash[entity] = hashes;
      currentRowId[entity] = ids;
      currentStamp[entity] = stamps;
    }
    final base = await _readBase(_db);
    final exported = await _readBase(_db, table: 'sync_exported');

    // Diff → ops. HLC stamps are minted per op via nextHlc
    // (its own transactions — never call it inside one of ours).
    final ops = <SyncOp>[];
    final opRowIds = <String, int>{}; // op_id → local row id (upserts)
    Future<void> mintOp(
      String entity,
      String syncId,
      String op,
      Map<String, Object?>? fields,
      int? rowId,
    ) async {
      // The op stamp is the row's own edit stamp when the store
      // stamped one after this device last SENT the row
      // (ReviewStore/LearnStore stamp at edit time): LWW must
      // compare EDIT times, or a device that merely EXPORTS
      // later would beat a device that EDITED later. Rows from
      // non-stamping stores (S1/S2) fall back to a fresh
      // export-time stamp — the documented limitation the
      // conflict copy backstops.
      //
      // The comparison baseline is the last SENT stamp
      // (sync_exported, falling back to the shared base), NOT
      // the base alone: since S7 review M1 the base no longer
      // advances at export, so for rows this device originated
      // the base can lag or be absent while the row's
      // updated_hlc merely echoes the last export's op stamp
      // (the recording transaction writes it back). Reusing
      // that echo would freeze every re-export at the FIRST
      // export's stamp and silently invert LWW.
      var hlc = await nextHlc(_db, at: at);
      if (op == 'upsert') {
        final rowStamp = currentStamp[entity]?[syncId];
        final sentHlc =
            exported[entity]?[syncId]?.hlc ?? base[entity]?[syncId]?.hlc;
        if (rowStamp != null &&
            (sentHlc == null || rowStamp.compareTo(sentHlc) > 0)) {
          hlc = rowStamp;
        }
      }
      final syncOp = SyncOp(
        opId: newUuid(),
        entity: entity,
        syncId: syncId,
        op: op,
        hlc: hlc,
        fields: fields,
      );
      ops.add(syncOp);
      if (rowId != null) opRowIds[syncOp.opId] = rowId;
    }

    // S7 review M1: the diff runs against what was last SENT
    // (sync_exported), falling back to the shared base for rows
    // never exported. sync_base itself is NOT advanced here —
    // it may only hold state both devices are known to share,
    // and an unacknowledged export is not shared. (v6 advanced
    // the base at export; when both devices exported before
    // either imported, each then misread the peer's op as a
    // fast-forward and edits silently swapped.)
    for (final entity in syncEntityOrder) {
      final baseFor = base[entity] ?? const {};
      final exportedFor = exported[entity] ?? const {};
      for (final entry in current[entity]!.entries) {
        final sent = exportedFor[entry.key] ?? baseFor[entry.key];
        if (full ||
            sent == null ||
            sent.deleted ||
            sent.hash != currentHash[entity]![entry.key]) {
          await mintOp(
            entity,
            entry.key,
            'upsert',
            current[entity]![entry.key],
            currentRowId[entity]![entry.key],
          );
        }
      }
      if (!full) {
        final sentIds = <String>{...baseFor.keys, ...exportedFor.keys};
        for (final syncId in sentIds) {
          final sent = exportedFor[syncId] ?? baseFor[syncId];
          if (sent != null &&
              !sent.deleted &&
              !current[entity]!.containsKey(syncId)) {
            await mintOp(entity, syncId, 'delete', null, null);
          }
        }
      }
    }

    final seqRows = await _db.query(
      'sync_meta',
      where: 'key = ?',
      whereArgs: ['export_seq'],
      limit: 1,
    );
    final seq =
        (seqRows.isEmpty ? 0 : int.parse(seqRows.single['value'] as String)) +
        1;

    if (ops.isEmpty) {
      await _setMeta('export_seq', '$seq');
      return SyncExportResult(file: null, opCount: 0, exportSeq: seq);
    }

    final opsJson = utf8.encode(
      jsonEncode({
        'ops': [for (final o in ops) o.toJson()],
      }),
    );
    final manifest = SyncManifest(
      formatVersion: formatVersion,
      deviceId: device,
      exportSeq: seq,
      createdAt: at.millisecondsSinceEpoch,
      full: full,
      opCount: ops.length,
      opsSha256: sha256.convert(opsJson).toString(),
    );
    final manifestBytes = utf8.encode(jsonEncode(manifest.toJson()));
    final archive = Archive()
      ..addFile(
        ArchiveFile('manifest.json', manifestBytes.length, manifestBytes),
      )
      ..addFile(ArchiveFile('ops.json', opsJson.length, opsJson));
    final zipBytes = ZipEncoder().encode(archive);

    final name =
        'pkg-${device.substring(0, 8)}-${seq.toString().padLeft(6, '0')}.zip';
    final library = LibraryStore(libraryRoot);
    await library.ensureLayout();
    final file = await library.writeAtomic('sync/$name', zipBytes);

    // Record: ops log, EXPORTED advance (never the shared base —
    // S7 review M1), row stamps, export meta — one transaction
    // so a crash cannot mark unsent state as sent (the file is
    // already written; a crash here just means the next export
    // re-sends, and import dedupes by op_id/state).
    await _db.transaction((txn) async {
      for (final o in ops) {
        await txn.insert('sync_ops', {
          'op_id': o.opId,
          'entity': o.entity,
          'sync_id': o.syncId,
          'op': o.op,
          'payload': o.fields == null ? null : jsonEncode(o.fields),
          'hlc': o.hlc,
          'device_id': device,
          'seq': seq,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        if (o.op == 'upsert') {
          await txn.insert('sync_exported', {
            'entity': o.entity,
            'sync_id': o.syncId,
            'content_hash': currentHash[o.entity]![o.syncId]!,
            'hlc': o.hlc,
            'deleted': 0,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
          final rowId = opRowIds[o.opId];
          if (rowId != null) {
            await txn.update(
              o.entity,
              {'updated_hlc': o.hlc},
              where: 'id = ?',
              whereArgs: [rowId],
            );
          }
        } else {
          await txn.insert('sync_exported', {
            'entity': o.entity,
            'sync_id': o.syncId,
            'content_hash': _deletedHash,
            'hlc': o.hlc,
            'deleted': 1,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
      await txn.insert('sync_meta', {
        'key': 'export_seq',
        'value': '$seq',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.insert('sync_meta', {
        'key': 'last_export_at',
        'value': '${at.millisecondsSinceEpoch}',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.insert('sync_meta', {
        'key': 'last_export_file',
        'value': name,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });

    return SyncExportResult(file: file, opCount: ops.length, exportSeq: seq);
  }

  // ---------------------------------------------------------- base / meta

  Future<void> _setMeta(String key, String value) async {
    await _db.insert('sync_meta', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, Map<String, ({String hash, String hlc, bool deleted})>>>
  _readBase(DatabaseExecutor db, {String table = 'sync_base'}) async {
    final rows = await db.query(table);
    final out =
        <String, Map<String, ({String hash, String hlc, bool deleted})>>{};
    for (final r in rows) {
      out.putIfAbsent(r['entity'] as String, () => {})[r['sync_id']
          as String] = (
        hash: r['content_hash'] as String,
        hlc: r['hlc'] as String,
        deleted: (r['deleted'] as int) == 1,
      );
    }
    return out;
  }

  Future<void> _writeBase(
    DatabaseExecutor db,
    String entity,
    String syncId, {
    required String hash,
    required String hlc,
    required bool deleted,
    String table = 'sync_base',
  }) async {
    await db.insert(table, {
      'entity': entity,
      'sync_id': syncId,
      'content_hash': hash,
      'hlc': hlc,
      'deleted': deleted ? 1 : 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// The import transaction's cached view of one entity's base
  /// rows (loaded once per entity per import).
  Future<Map<String, ({String hash, String hlc, bool deleted})>> _baseFor(
    _MergeCtx ctx,
    String entity,
  ) async {
    final cached = ctx.base[entity];
    if (cached != null) return cached;
    final rows = await ctx.txn.query(
      'sync_base',
      where: 'entity = ?',
      whereArgs: [entity],
    );
    final map = <String, ({String hash, String hlc, bool deleted})>{
      for (final r in rows)
        r['sync_id'] as String: (
          hash: r['content_hash'] as String,
          hlc: r['hlc'] as String,
          deleted: (r['deleted'] as int) == 1,
        ),
    };
    ctx.base[entity] = map;
    return map;
  }

  /// Record a state BOTH devices now hold (an import outcome
  /// that applied the peer state wholesale): advances sync_base
  /// AND sync_exported (our last-sent view becomes the same
  /// state, so we never re-send it), keeping the import
  /// transaction's cache coherent. Local-win outcomes never call
  /// this — the winning state still has to travel (see D-029).
  Future<void> _setShared(
    _MergeCtx ctx,
    String entity,
    String syncId, {
    required String hash,
    required String hlc,
    required bool deleted,
  }) async {
    await _writeBase(
      ctx.txn,
      entity,
      syncId,
      hash: hash,
      hlc: hlc,
      deleted: deleted,
    );
    await _writeBase(
      ctx.txn,
      entity,
      syncId,
      hash: hash,
      hlc: hlc,
      deleted: deleted,
      table: 'sync_exported',
    );
    final cached = ctx.base[entity];
    if (cached != null) {
      cached[syncId] = (hash: hash, hlc: hlc, deleted: deleted);
    }
  }

  // ---------------------------------------------------------- HLC helpers

  /// (wallMs, counter) of a formatHlc stamp; (-1, -1) if unparseable.
  static (int, int) _parseHlc(String hlc) {
    final parts = hlc.split('-');
    if (parts.length < 2) return (-1, -1);
    return (int.tryParse(parts[0]) ?? -1, int.tryParse(parts[1]) ?? -1);
  }

  /// Advance this device's HLC state by stamps SEEN from a peer,
  /// with the wall clamped to local time (receiver clamping): a
  /// fast peer clock must not drag this device's stamps forward.
  Future<void> _observeStamps(
    Transaction txn,
    Iterable<String> stamps,
    int nowMs,
  ) async {
    var seenWall = -1;
    var seenCounter = -1;
    for (final s in stamps) {
      final (w, c) = _parseHlc(s);
      if (w > seenWall || (w == seenWall && c > seenCounter)) {
        seenWall = w;
        seenCounter = c;
      }
    }
    if (seenWall < 0) return;
    final clampedWall = seenWall > nowMs ? nowMs : seenWall;
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
    final wall = clampedWall > lastWall ? clampedWall : lastWall;
    final counter = wall == lastWall
        ? (clampedWall == lastWall && seenCounter > lastCounter
              ? seenCounter
              : lastCounter)
        : seenCounter;
    await txn.insert('sync_meta', {
      'key': 'hlc_state',
      'value': '$wall:$counter',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ---------------------------------------------------------- import

  /// Validate a package file WITHOUT applying anything.
  Future<SyncManifest> inspectPackage(File zip) async {
    final (_, manifest) = await _decode(zip);
    return manifest;
  }

  Future<(List<SyncOp>, SyncManifest)> _decode(File zip) async {
    if (!await zip.exists()) {
      throw SyncException('Sync package not found.');
    }
    if (await zip.length() > maxZipBytes) {
      throw SyncException('Sync package is unreasonably large.');
    }
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(await zip.readAsBytes());
    } catch (_) {
      throw SyncException('That file is not a readable sync package.');
    }
    for (final entry in archive.files) {
      final name = entry.name;
      final bad =
          name.startsWith('/') ||
          name.contains('\\') ||
          name.split('/').any((seg) => seg == '..' || seg == '.');
      if (bad) {
        throw SyncException('Sync package contains an unsafe path: $name');
      }
    }
    final manifestFile = archive.findFile('manifest.json');
    final opsFile = archive.findFile('ops.json');
    if (manifestFile == null || opsFile == null) {
      throw SyncException('Sync package is missing its contents.');
    }
    // S7 review S4: check DECLARED sizes before touching
    // `.content` (which inflates the entry): the 64 MB compressed
    // cap alone would let a small zip bomb expand to gigabytes
    // in memory on Sync-now. BackupStore checks entry.size the
    // same way.
    if (manifestFile.size > 1024 * 1024 || opsFile.size > maxOpsBytes) {
      throw SyncException('Sync package is unreasonably large.');
    }
    final SyncManifest manifest;
    final List<SyncOp> ops;
    try {
      manifest = SyncManifest.fromJson(
        (jsonDecode(utf8.decode(manifestFile.content)) as Map)
            .cast<String, Object?>(),
      );
      final opsBytes = opsFile.content;
      if (opsBytes.length > maxOpsBytes) {
        throw SyncException('Sync package is unreasonably large.');
      }
      if (sha256.convert(opsBytes).toString() != manifest.opsSha256) {
        throw SyncException(
          'Sync package is damaged (contents do not match its manifest).',
        );
      }
      final decoded = jsonDecode(utf8.decode(opsBytes)) as Map;
      ops = [
        for (final raw in (decoded['ops'] as List))
          SyncOp.fromJson((raw as Map).cast<String, Object?>()),
      ];
    } on SyncException {
      rethrow;
    } catch (_) {
      throw SyncException('Sync package is unreadable.');
    }
    if (manifest.formatVersion < 1) {
      throw SyncException('Sync package has an invalid format version.');
    }
    if (manifest.formatVersion > formatVersion) {
      throw SyncException(
        'This package uses a newer sync format (format '
        '${manifest.formatVersion}, this app understands '
        '$formatVersion). Update the app first.',
      );
    }
    if (ops.length != manifest.opCount) {
      throw SyncException(
        'Sync package is damaged (op count does not match its manifest).',
      );
    }
    for (final o in ops) {
      if (!_specs.containsKey(o.entity)) {
        throw SyncException(
          'Sync package mentions an unknown kind of data: ${o.entity}.',
        );
      }
    }
    return (ops, manifest);
  }

  /// Import one package. Atomic: any [SyncException] (or database
  /// error) leaves the database exactly as it was.
  Future<SyncImportReport> importPackage(File zip, {DateTime? now}) async {
    final at = now ?? DateTime.now();
    final nowMs = at.millisecondsSinceEpoch;
    final (ops, manifest) = await _decode(zip);
    final report = SyncImportReport();
    var touchedDailyLoop = false;
    String? maxAppliedHlc;

    // Order: upserts parents-first, then deletes children-first.
    final order = {
      for (var i = 0; i < syncEntityOrder.length; i++) syncEntityOrder[i]: i,
    };
    final upserts = ops.where((o) => o.op == 'upsert').toList()
      ..sort((a, b) => order[a.entity]!.compareTo(order[b.entity]!));
    final deletes = ops.where((o) => o.op == 'delete').toList()
      ..sort((a, b) => order[b.entity]!.compareTo(order[a.entity]!));

    // S7 review S1: only stamps from ops that will actually be
    // CONSIDERED may advance this device's HLC state. A package
    // whose ops are all quarantined (a wrong-clock peer) must
    // leave the local clock state exactly as it was — stamping
    // from held ops would let a quarantined package move local
    // state it was never trusted with.
    final cleanStamps = [
      for (final o in ops)
        if (_quarantineReason(o, at) == null) o.hlc,
    ];
    try {
      await _db.transaction((txn) async {
        await _observeStamps(txn, cleanStamps, nowMs);
        final ctx = _MergeCtx(txn, at, report, sourceDevice: manifest.deviceId);
        for (final op in [...upserts, ...deletes]) {
          final seen = await txn.query(
            'sync_ops',
            where: 'op_id = ?',
            whereArgs: [op.opId],
            limit: 1,
          );
          if (seen.isNotEmpty) {
            report.duplicates++;
            continue;
          }
          final quarantineReason = _quarantineReason(op, at);
          if (quarantineReason != null) {
            final existing = await txn.query(
              'sync_quarantine',
              where: 'op_id = ?',
              whereArgs: [op.opId],
              limit: 1,
            );
            if (existing.isEmpty) {
              await txn.insert('sync_quarantine', {
                'op_id': op.opId,
                'entity': op.entity,
                'sync_id': op.syncId,
                'hlc': op.hlc,
                'payload': op.fields == null ? null : jsonEncode(op.fields),
                'reason': quarantineReason,
                'source_device': manifest.deviceId,
                'received_at': nowMs,
              });
              report.quarantined++;
            } else {
              report.alreadyQuarantined++;
            }
            continue; // NOT recorded in sync_ops: re-import re-evaluates.
          }
          var appliedOk = true;
          // Per-op SAVEPOINT: if applying one op fails at the
          // database level (a constraint the merge rules did not
          // foresee), THAT op rolls back and is quarantined for
          // inspection instead of aborting the whole package
          // forever (S7 review M3 backstop).
          await txn.execute('SAVEPOINT sync_op');
          try {
            if (op.op == 'upsert') {
              appliedOk = await _applyUpsert(ctx, op);
            } else {
              await _applyDelete(ctx, op);
            }
            await txn.execute('RELEASE sync_op');
          } on DatabaseException catch (e) {
            await txn.execute('ROLLBACK TO sync_op');
            await txn.execute('RELEASE sync_op');
            ctx.idMap.remove('${op.entity}:${op.syncId}');
            await _quarantineOp(ctx, op, 'apply-error: $e');
            continue;
          }
          if (!appliedOk) {
            continue; // quarantined as missing-parent inside
          }
          await txn.insert('sync_ops', {
            'op_id': op.opId,
            'entity': op.entity,
            'sync_id': op.syncId,
            'op': op.op,
            'payload': op.fields == null ? null : jsonEncode(op.fields),
            'hlc': op.hlc,
            'device_id': manifest.deviceId,
            'seq': manifest.exportSeq,
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
          // A previously-quarantined op that now applies leaves quarantine.
          await txn.delete(
            'sync_quarantine',
            where: 'op_id = ?',
            whereArgs: [op.opId],
          );
          final prevMax = maxAppliedHlc;
          if (prevMax == null || op.hlc.compareTo(prevMax) > 0) {
            maxAppliedHlc = op.hlc;
          }
          if (op.entity == 'day_reviews' ||
              op.entity == 'day_plans' ||
              op.entity == 'day_plan_items') {
            touchedDailyLoop = true;
          }
        }
        // Peer high-water mark: what we have imported from the source.
        if (maxAppliedHlc != null) {
          await txn.insert('sync_peers', {
            'device_id': manifest.deviceId,
            'last_import_hlc': maxAppliedHlc,
            'last_import_at': nowMs,
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
          await txn.update(
            'sync_peers',
            {'last_import_hlc': maxAppliedHlc, 'last_import_at': nowMs},
            where: 'device_id = ?',
            whereArgs: [manifest.deviceId],
          );
        }
      });
    } on DatabaseException catch (e) {
      // Nothing was committed (single transaction). Surface a
      // sync-level error, never a raw database one.
      throw SyncException(
        'Sync package could not be applied; nothing was changed. ($e)',
      );
    }

    if (touchedDailyLoop) {
      // Derived data re-derives: imported reviews/plan items may
      // change counted-ness, shields, and scores' presentation.
      await ReviewStore(_db, TodayStore(_db)).evaluate(now: at);
      report.streakReevaluated = true;
    }
    return report;
  }

  /// Why an op must be held out, or null when it may apply.
  String? _quarantineReason(SyncOp op, DateTime now) {
    final (wall, _) = _parseHlc(op.hlc);
    final horizon = now.add(futureHorizon).millisecondsSinceEpoch;
    if (wall > horizon) return 'future-hlc';
    final spec = _specs[op.entity]!;
    if (spec.naturalKey != null && op.fields != null) {
      final dateStr = op.fields![spec.naturalKey] as String?;
      if (dateStr != null) {
        final d = DateTime.tryParse(dateStr);
        if (d != null) {
          final today = DateTime(now.year, now.month, now.day);
          if (d.isAfter(today.add(futureHorizon))) return 'future-date';
        }
      }
    }
    return null;
  }

  /// Import every package in `Library/sync/` that came from the
  /// OTHER device (the folder-sync drop point), oldest name first.
  /// Own exports are skipped by filename; op_id dedupe is the
  /// real guard underneath.
  Future<SyncImportReport> importFromSyncFolder({
    required Directory libraryRoot,
    DateTime? now,
  }) async {
    final combined = SyncImportReport();
    final device = await AppDatabase.deviceId(_db);
    final dir = Directory(p.join(libraryRoot.path, 'sync'));
    if (!await dir.exists()) return combined;
    final files = await dir
        .list()
        .where((e) => e is File && e.path.endsWith('.zip'))
        .cast<File>()
        .toList();
    files.sort((a, b) => a.path.compareTo(b.path));
    for (final f in files) {
      if (p.basename(f.path).startsWith('pkg-${device.substring(0, 8)}-')) {
        continue; // our own export
      }
      // S7 review S3: one bad file in the folder (a corrupt zip,
      // a stray backup archive) must not block every package
      // sorted after it, forever. Skip it, NAME it in the
      // report, and carry on.
      final SyncImportReport r;
      try {
        r = await importPackage(f, now: now);
      } catch (_) {
        combined.failedFiles.add(p.basename(f.path));
        continue;
      }
      combined.applied += r.applied;
      combined.duplicates += r.duplicates;
      combined.keptLocal += r.keptLocal;
      combined.conflicts += r.conflicts;
      combined.quarantined += r.quarantined;
      combined.alreadyQuarantined += r.alreadyQuarantined;
      combined.stale += r.stale;
      combined.streakReevaluated =
          combined.streakReevaluated || r.streakReevaluated;
    }
    return combined;
  }

  // ---------------------------------------------------------- merge internals

  /// Insert a visible conflict copy. The row's own updated_hlc is
  /// the winning op's stamp (nextHlc cannot run inside the import
  /// transaction — sqflite forbids nested transactions).
  Future<void> _recordConflict(
    _MergeCtx ctx, {
    required String entity,
    required String rowSyncId,
    required String kind,
    Map<String, Object?>? kept,
    Map<String, Object?>? lost,
    String? keptRaw,
    String? lostRaw,
  }) async {
    ctx.report.conflicts++;
    await ctx.txn.insert('sync_conflicts', {
      'entity': entity,
      'row_sync_id': rowSyncId,
      'kind': kind,
      'field': null,
      'kept_text': keptRaw ?? (kept == null ? null : jsonEncode(kept)),
      'lost_text': lostRaw ?? (lost == null ? null : jsonEncode(lost)),
      'created_at': ctx.at.millisecondsSinceEpoch,
      'sync_id': newUuid(),
      'updated_hlc': ctx.stampHlc,
    });
  }

  /// Resolve a payload `<column>_sync` reference to a local id:
  /// this import's alias map first (natural-key adoptions), then
  /// the parent table by sync_id. Null when unresolvable.
  Future<int?> _resolveParent(
    _MergeCtx ctx,
    _Fk fk,
    Map<String, Object?> payload,
  ) async {
    final ref = payload['${fk.column}_sync'];
    if (ref == null) return null;
    final syncId = ref as String;
    final aliased = ctx.idMap['${fk.parent}:$syncId'];
    if (aliased != null) return aliased;
    final rows = await ctx.txn.query(
      fk.parent,
      columns: ['id'],
      where: 'sync_id = ?',
      whereArgs: [syncId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.single['id'] as int;
  }

  /// Materialise a row map from a payload. Returns null when a
  /// REQUIRED parent cannot be resolved (caller quarantines).
  Future<Map<String, Object?>?> _rowFromPayload(
    _MergeCtx ctx,
    SyncOp op,
  ) async {
    final spec = _specs[op.entity]!;
    final fields = op.fields!;
    final row = <String, Object?>{};
    for (final f in spec.fields) {
      row[f] = fields[f];
    }
    for (final fk in spec.fks) {
      final ref = fields['${fk.column}_sync'];
      if (ref == null) {
        row[fk.column] = null;
        continue;
      }
      final id = await _resolveParent(ctx, fk, fields);
      if (id == null) {
        // Nullable FKs degrade to null (the row and its content
        // survive; the link is re-creatable). NOT NULL FKs are
        // structural: without the parent the row is meaningless.
        const nullableFks = {
          'day_plan_items.template_id',
          // D-042: a task whose linked item cannot be resolved
          // (not yet imported — plan_templates travel before
          // items — or deleted on the sender) degrades to a
          // plain task. It must never be quarantined.
          'day_plan_items.item_id',
          'plan_templates.item_id',
          'marked_points.question_id',
          'questions.source_id',
          'packs.source_id',
          'learn_sessions.topic_id',
          'day_reviews.major_point_topic_id',
        };
        if (!nullableFks.contains('${op.entity}.${fk.column}')) {
          return null;
        }
        row[fk.column] = null;
      } else {
        row[fk.column] = id;
      }
    }
    if (op.entity == 'review_log') {
      final qKey = fields['question_key'];
      var questionId = 0;
      if (qKey is String) {
        final q = await ctx.txn.query(
          'questions',
          columns: ['id'],
          where: 'sync_id = ?',
          whereArgs: [qKey],
          limit: 1,
        );
        if (q.isNotEmpty) questionId = q.single['id'] as int;
      }
      row['question_id'] = questionId;
      final sessionRef = fields['session_id_sync'];
      int? sessionId;
      if (sessionRef is String) {
        sessionId = await _resolveParent(
          ctx,
          const _Fk('session_id', 'learn_sessions'),
          fields,
        );
      }
      row['session_id'] = sessionId;
    }
    if (op.entity == 'day_plans') {
      // D-042 fix, found by the plan-link round-trip test:
      // day_plans.created_at is NOT NULL but not a synced
      // field, so inserting a plan onto a device that never
      // generated that date failed the constraint and the op
      // landed in quarantine (masked while both devices
      // generated the same morning locally). Materialise it
      // from the op's own stamp — the moment the plan was
      // created on the origin device, near enough for a
      // bookkeeping column nothing reads for logic.
      row['created_at'] =
          int.tryParse(op.hlc.split('-').first) ??
              DateTime.now().millisecondsSinceEpoch;
    }
    row['sync_id'] = op.syncId;
    row['updated_hlc'] = op.hlc;
    row['deleted_at_hlc'] = null;
    return row;
  }

  /// Find the local row an op refers to: by sync_id; for
  /// natural-key entities also by date (with identity adoption);
  /// for routine day-plan items also by (plan, template).
  Future<Map<String, Object?>?> _findLocal(_MergeCtx ctx, SyncOp op) async {
    final txn = ctx.txn;
    final bySync = await txn.query(
      op.entity,
      where: 'sync_id = ?',
      whereArgs: [op.syncId],
      limit: 1,
    );
    if (bySync.isNotEmpty) return bySync.single;
    final spec = _specs[op.entity]!;
    if (spec.naturalKey != null && op.fields != null) {
      final key = op.fields![spec.naturalKey] as String?;
      if (key != null) {
        final byKey = await txn.query(
          op.entity,
          where: '${spec.naturalKey} = ?',
          whereArgs: [key],
          limit: 1,
        );
        if (byKey.isNotEmpty) {
          await _adoptIdentity(ctx, op, byKey.single);
          return {...byKey.single, 'sync_id': op.syncId};
        }
      }
    }
    if (op.entity == 'packs' && op.fields != null) {
      // S7 review M3: both devices importing the same .quizpack
      // file is an EXPECTED flow (the file travels in the
      // Library), and the importer mints a fresh random sync_id
      // per device. Without adoption by pack_id, cross-import
      // inserts a second row, hits UNIQUE(pack_id), and (before
      // the per-op savepoint) aborted the whole package forever.
      final packId = op.fields!['pack_id'] as String?;
      if (packId != null) {
        final byPack = await txn.query(
          'packs',
          where: 'pack_id = ?',
          whereArgs: [packId],
          limit: 1,
        );
        if (byPack.isNotEmpty) {
          await _adoptIdentity(ctx, op, byPack.single);
          return {...byPack.single, 'sync_id': op.syncId};
        }
      }
    }
    if (op.entity == 'questions' && op.fields != null) {
      final packId = op.fields!['pack_id'] as String?;
      final qid = op.fields!['pack_qid'] as String?;
      if (packId != null && qid != null) {
        final byQ = await txn.query(
          'questions',
          where: 'pack_id = ? AND pack_qid = ?',
          whereArgs: [packId, qid],
          limit: 1,
        );
        if (byQ.isNotEmpty) {
          await _adoptIdentity(ctx, op, byQ.single);
          return {...byQ.single, 'sync_id': op.syncId};
        }
      }
    }
    if (op.entity == 'day_plan_items' &&
        op.fields != null &&
        op.fields!['kind'] == 'routine') {
      final planId = await _resolveParent(
        ctx,
        const _Fk('day_plan_id', 'day_plans'),
        op.fields!,
      );
      final templateId = await _resolveParent(
        ctx,
        const _Fk('template_id', 'plan_templates'),
        op.fields!,
      );
      final position = op.fields!['position'];
      if (planId != null && templateId != null && position is int) {
        // S7 review S3: adoption is a GUESS that two rows are the
        // same generated item, so it keys on the full natural
        // slot (plan + template + position) and must match
        // exactly one row — adopting by template alone could fuse
        // two different items sharing a template (possible in
        // mixed fleets where a NULL deterministic id was randomly
        // stamped at open on one device).
        final match = await txn.query(
          'day_plan_items',
          where:
              'day_plan_id = ? AND template_id = ? AND kind = ? '
              'AND position = ?',
          whereArgs: [planId, templateId, 'routine', position],
        );
        if (match.length == 1) {
          await _adoptIdentity(ctx, op, match.single);
          return {...match.single, 'sync_id': op.syncId};
        }
      }
    }
    return null;
  }

  /// A local row created independently (same date / same routine
  /// slot) takes the incoming sync_id as its identity, so future
  /// ops and child references line up. Its old base entry (if
  /// any) migrates to the new key.
  Future<void> _adoptIdentity(
    _MergeCtx ctx,
    SyncOp op,
    Map<String, Object?> localRow,
  ) async {
    final oldSyncId = localRow['sync_id'] as String?;
    final localId = localRow['id'] as int;
    ctx.idMap['${op.entity}:${op.syncId}'] = localId;
    if (oldSyncId == op.syncId) return;
    await ctx.txn.update(
      op.entity,
      {'sync_id': op.syncId},
      where: 'id = ?',
      whereArgs: [localId],
    );
    if (oldSyncId != null) {
      final oldBase = await ctx.txn.query(
        'sync_base',
        where: 'entity = ? AND sync_id = ?',
        whereArgs: [op.entity, oldSyncId],
        limit: 1,
      );
      if (oldBase.isNotEmpty) {
        await ctx.txn.delete(
          'sync_base',
          where: 'entity = ? AND sync_id = ?',
          whereArgs: [op.entity, oldSyncId],
        );
        await ctx.txn.insert('sync_base', {
          ...oldBase.single,
          'sync_id': op.syncId,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        (await _baseFor(ctx, op.entity))[op.syncId] = (
          hash: oldBase.single['content_hash'] as String,
          hlc: oldBase.single['hlc'] as String,
          deleted: (oldBase.single['deleted'] as int) == 1,
        );
      }
    }
  }

  /// Apply one upsert op. Returns false when the op had to be
  /// quarantined instead (missing required parent).
  Future<bool> _applyUpsert(_MergeCtx ctx, SyncOp op) async {
    final txn = ctx.txn;
    final spec = _specs[op.entity]!;
    final remoteHash = _hash(op.fields!);
    final base = (await _baseFor(ctx, op.entity))[op.syncId];
    final local = await _findLocal(ctx, op);

    if (op.entity == 'day_reviews' && local != null) {
      return _mergeDayReview(ctx, op, local, remoteHash);
    }

    if (local == null) {
      if (base != null && !base.deleted && op.hlc.compareTo(base.hlc) <= 0) {
        // S7 review S2: the row is locally gone and this op is
        // NOT newer than the state both devices already shared —
        // a stale package replayed out of order. Applying it
        // would resurrect superseded content.
        ctx.report.stale++;
        return true;
      }
      if (base != null && !base.deleted) {
        // The row existed at last sync and is gone here: a local
        // delete the exporter hasn't packaged yet.
        if (remoteHash == base.hash) {
          // Peer changed nothing; the local delete stands. Base
          // deliberately NOT touched: the shared state is still
          // the live row, so our next export must still emit the
          // delete — marking the base deleted here would suppress
          // that op and the peer would keep the row forever.
          ctx.report.keptLocal++;
          return true;
        }
        // Peer EDITED a row we deleted: resurrect theirs, and
        // record that our delete lost (visible, not silent).
        final row = await _rowFromPayload(ctx, op);
        if (row == null) return _quarantineMissingParent(ctx, op);
        await txn.insert(op.entity, row);
        await _recordConflict(
          ctx,
          entity: op.entity,
          rowSyncId: op.syncId,
          kind: 'delete-vs-edit',
          kept: op.fields,
          lostRaw: '(deleted on this device)',
        );
        await _setShared(
          ctx,
          op.entity,
          op.syncId,
          hash: remoteHash,
          hlc: op.hlc,
          deleted: false,
        );
        ctx.report.applied++;
        return true;
      }
      final row = await _rowFromPayload(ctx, op);
      if (row == null) return _quarantineMissingParent(ctx, op);
      // Append-only tables ignore a UNIQUE collision on insert:
      // for immutable history, the row already being here IS
      // the same fact.
      await txn.insert(
        op.entity,
        row,
        conflictAlgorithm: spec.appendOnly
            ? ConflictAlgorithm.ignore
            : ConflictAlgorithm.abort,
      );
      await _setShared(
        ctx,
        op.entity,
        op.syncId,
        hash: remoteHash,
        hlc: op.hlc,
        deleted: false,
      );
      ctx.report.applied++;
      return true;
    }

    // Local row exists.
    final localPayload = await _payloadOf(txn, op.entity, local);
    final localHash = _hash(localPayload);
    final localChanged = base == null || base.deleted || localHash != base.hash;
    final remoteChanged =
        base == null || base.deleted || remoteHash != base.hash;

    if (!localChanged && !remoteChanged) {
      ctx.report.keptLocal++;
      return true;
    }
    if (!localChanged) {
      if (op.hlc.compareTo(base.hlc) <= 0) {
        // S7 review S2: payload differs from base but the stamp
        // does not postdate it — an older package imported after
        // a newer one. Never roll a row backwards.
        ctx.report.stale++;
        return true;
      }
      // Fast-forward: we never touched it since base.
      final row = await _rowFromPayload(ctx, op);
      if (row == null) return _quarantineMissingParent(ctx, op);
      row.remove('sync_id');
      await txn.update(
        op.entity,
        row,
        where: 'id = ?',
        whereArgs: [local['id']],
      );
      await _setShared(
        ctx,
        op.entity,
        op.syncId,
        hash: remoteHash,
        hlc: op.hlc,
        deleted: false,
      );
      ctx.report.applied++;
      return true;
    }
    if (!remoteChanged) {
      ctx.report.keptLocal++;
      return true;
    }
    if (localHash == remoteHash) {
      // Both sides made the SAME change independently: converge.
      await _setShared(
        ctx,
        op.entity,
        op.syncId,
        hash: remoteHash,
        hlc: op.hlc,
        deleted: false,
      );
      ctx.report.keptLocal++;
      return true;
    }

    // Both changed, differently.
    if (spec.appendOnly) {
      // Immutable history must not be rewritten; keep ours, keep
      // theirs as a conflict copy so nothing is lost anywhere.
      await _recordConflict(
        ctx,
        entity: op.entity,
        rowSyncId: op.syncId,
        kind: 'append-only-divergence',
        kept: localPayload,
        lost: op.fields,
      );
      // Base NOT advanced: our version still has to travel.
      return true;
    }
    if (op.entity == 'day_plan_items' &&
        _onlyDoneDiffers(localPayload, op.fields!)) {
      // A toggle's last action is the intent (§R7.2): LWW on the
      // done flag only, no conflict copy.
      final localStamp = (local['updated_hlc'] as String?) ?? '';
      if (op.hlc.compareTo(localStamp) > 0) {
        await txn.update(
          op.entity,
          {'done': op.fields!['done'], 'updated_hlc': op.hlc},
          where: 'id = ?',
          whereArgs: [local['id']],
        );
        final merged = {...localPayload, 'done': op.fields!['done']};
        await _setShared(
          ctx,
          op.entity,
          op.syncId,
          hash: _hash(merged),
          hlc: op.hlc,
          deleted: false,
        );
        ctx.report.applied++;
      } else {
        // Base NOT advanced: our winning toggle still has to travel.
        ctx.report.keptLocal++;
      }
      return true;
    }

    // Generic mutable conflict: LWW by HLC for the live row; the
    // losing payload is preserved as a conflict copy either way.
    final localStamp = (local['updated_hlc'] as String?) ?? '';
    if (op.hlc.compareTo(localStamp) > 0) {
      final row = await _rowFromPayload(ctx, op);
      if (row == null) return _quarantineMissingParent(ctx, op);
      row.remove('sync_id');
      await txn.update(
        op.entity,
        row,
        where: 'id = ?',
        whereArgs: [local['id']],
      );
      await _recordConflict(
        ctx,
        entity: op.entity,
        rowSyncId: op.syncId,
        kind: 'edit-edit',
        kept: op.fields,
        lost: localPayload,
      );
      await _setShared(
        ctx,
        op.entity,
        op.syncId,
        hash: remoteHash,
        hlc: op.hlc,
        deleted: false,
      );
      ctx.report.applied++;
    } else {
      await _recordConflict(
        ctx,
        entity: op.entity,
        rowSyncId: op.syncId,
        kind: 'edit-edit',
        kept: localPayload,
        lost: op.fields,
      );
      // Base NOT advanced: our winning version still has to
      // travel — advancing it here would strand the peer on its
      // losing version forever (permanent divergence).
      ctx.report.keptLocal++;
    }
    return true;
  }

  bool _onlyDoneDiffers(Map<String, Object?> a, Map<String, Object?> b) {
    final keys = {...a.keys, ...b.keys};
    for (final k in keys) {
      if (k == 'done') continue;
      if (a[k] != b[k]) return false;
    }
    return a['done'] != b['done'];
  }

  /// day_reviews merge per DATE (red-team correction to §R7.2):
  /// scores by HLC; a major point is never erased by a null;
  /// two different points → conflict copy of the loser.
  Future<bool> _mergeDayReview(
    _MergeCtx ctx,
    SyncOp op,
    Map<String, Object?> local,
    String remoteHash,
  ) async {
    final txn = ctx.txn;
    final localPayload = await _payloadOf(txn, 'day_reviews', local);
    final localHash = _hash(localPayload);
    if (localHash == remoteHash) {
      await _setShared(
        ctx,
        'day_reviews',
        op.syncId,
        hash: remoteHash,
        hlc: op.hlc,
        deleted: false,
      );
      ctx.report.keptLocal++;
      return true;
    }
    final remote = op.fields!;
    final localStamp = (local['updated_hlc'] as String?) ?? '';
    final remoteWins = op.hlc.compareTo(localStamp) > 0;
    final winner = remoteWins ? remote : localPayload;
    final loser = remoteWins ? localPayload : remote;

    final merged = <String, Object?>{...localPayload};
    for (final f in const [
      'self_score',
      'self_note',
      'done_score',
      'score_formula_version',
      'closed_at',
      'tz_offset',
    ]) {
      merged[f] = winner[f];
    }
    final winnerPoint = winner['major_point'] as String?;
    final loserPoint = loser['major_point'] as String?;
    if (winnerPoint != null) {
      merged['major_point'] = winnerPoint;
      merged['major_point_topic_id_sync'] = winner['major_point_topic_id_sync'];
      if (loserPoint != null && loserPoint != winnerPoint) {
        await _recordConflict(
          ctx,
          entity: 'day_reviews',
          rowSyncId: op.syncId,
          kind: 'major-point',
          keptRaw: winnerPoint,
          lostRaw: loserPoint,
        );
      }
    } else if (loserPoint != null) {
      // The HLC winner never wrote a point; keep the loser's —
      // content is never erased by an absence.
      merged['major_point'] = loserPoint;
      merged['major_point_topic_id_sync'] = loser['major_point_topic_id_sync'];
    }

    // S7 review S1: the same never-silently-drop rule covers the
    // hand-written self_note — the score fields are winner-take-
    // all by §R7.2 design, but a differing loser note is TEXT the
    // owner wrote, so it is preserved as a conflict copy.
    final winnerNote = winner['self_note'] as String?;
    final loserNote = loser['self_note'] as String?;
    if (loserNote != null && loserNote != winnerNote) {
      await _recordConflict(
        ctx,
        entity: 'day_reviews',
        rowSyncId: op.syncId,
        kind: 'self-note',
        keptRaw: winnerNote,
        lostRaw: loserNote,
      );
    }

    final mergedOp = SyncOp(
      opId: op.opId,
      entity: 'day_reviews',
      syncId: op.syncId,
      op: 'upsert',
      hlc: op.hlc,
      fields: merged,
    );
    final row = await _rowFromPayload(ctx, mergedOp);
    if (row == null) return _quarantineMissingParent(ctx, op);
    row.remove('sync_id');
    row['updated_hlc'] = remoteWins
        ? op.hlc
        : (local['updated_hlc'] as String? ?? op.hlc);
    await txn.update(
      'day_reviews',
      row,
      where: 'id = ?',
      whereArgs: [local['id']],
    );
    // Base NOT advanced: the merged review is a NEW state neither
    // device held before; it must travel back to the peer via our
    // next export, or the two reviews diverge permanently.
    ctx.report.applied++;
    return true;
  }

  Future<bool> _quarantineMissingParent(_MergeCtx ctx, SyncOp op) {
    return _quarantineOp(ctx, op, 'missing-parent');
  }

  Future<bool> _quarantineOp(_MergeCtx ctx, SyncOp op, String reason) async {
    await ctx.txn.insert('sync_quarantine', {
      'op_id': op.opId,
      'entity': op.entity,
      'sync_id': op.syncId,
      'hlc': op.hlc,
      'payload': op.fields == null ? null : jsonEncode(op.fields),
      'reason': reason,
      'source_device': ctx.sourceDevice,
      'received_at': ctx.at.millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    ctx.report.quarantined++;
    return false;
  }

  /// Child specs of [parent] (entity + FK column), derived from
  /// the spec table's foreign keys.
  List<({String entity, String fkColumn})> _childSpecsOf(String parent) {
    return [
      for (final e in _specs.entries)
        for (final fk in e.value.fks)
          if (fk.parent == parent) (entity: e.key, fkColumn: fk.column),
    ];
  }

  /// S7 review M4: the first descendant of (`entity`, `id`) whose
  /// local state differs from its shared base (or which has no
  /// base — created here and never shared), or null when the
  /// whole subtree is exactly as shared and safe to cascade.
  Future<String?> _firstDivergedDescendant(
    _MergeCtx ctx,
    String entity,
    int id,
  ) async {
    final queue = <(String, int)>[(entity, id)];
    final seen = <String>{'$entity:$id'};
    while (queue.isNotEmpty) {
      final (e, localId) = queue.removeAt(0);
      for (final child in _childSpecsOf(e)) {
        final rows = await ctx.txn.query(
          child.entity,
          where: '${child.fkColumn} = ?',
          whereArgs: [localId],
        );
        for (final row in rows) {
          if (row['deleted_at_hlc'] != null) continue;
          final syncId = row['sync_id'] as String?;
          if (syncId == null) {
            return '${child.entity} row without sync identity';
          }
          final childBase = (await _baseFor(ctx, child.entity))[syncId];
          final payload = await _payloadOf(ctx.txn, child.entity, row);
          if (childBase == null ||
              childBase.deleted ||
              childBase.hash != _hash(payload)) {
            return '${child.entity} "$syncId" differs from the shared state';
          }
          if (seen.add('${child.entity}:${row['id']}')) {
            queue.add((child.entity, row['id'] as int));
          }
        }
      }
    }
    return null;
  }

  Future<void> _applyDelete(_MergeCtx ctx, SyncOp op) async {
    final txn = ctx.txn;
    final local = await _findLocal(ctx, op);
    final base = (await _baseFor(ctx, op.entity))[op.syncId];
    if (local == null) {
      if (base != null && !base.deleted && op.hlc.compareTo(base.hlc) <= 0) {
        // Stale delete (S7 review S2): not newer than the shared
        // state — do not even tombstone from it.
        ctx.report.stale++;
        return;
      }
      await _setShared(
        ctx,
        op.entity,
        op.syncId,
        hash: _deletedHash,
        hlc: op.hlc,
        deleted: true,
      );
      ctx.report.keptLocal++;
      return;
    }
    final localPayload = await _payloadOf(txn, op.entity, local);
    final localHash = _hash(localPayload);
    final localChanged = base == null || base.deleted || localHash != base.hash;
    if (!localChanged) {
      if (op.hlc.compareTo(base.hlc) <= 0) {
        ctx.report.stale++;
        return;
      }
      // S7 review M4: the delete cascades by FK — but only over
      // children that are exactly as shared. A descendant this
      // device created or edited since the base (or never
      // shared) would die silently, with no conflict copy and
      // no future op ever mentioning it. Hold the delete as a
      // conflict instead: the subtree stays, the loss is
      // visible, and convergence continues via the children.
      final diverged = await _firstDivergedDescendant(
        ctx,
        op.entity,
        local['id'] as int,
      );
      if (diverged != null) {
        await _recordConflict(
          ctx,
          entity: op.entity,
          rowSyncId: op.syncId,
          kind: 'delete-with-unsynced-children',
          kept: localPayload,
          lostRaw: '(deleted on the other device)',
        );
        ctx.report.keptLocal++;
        return;
      }
      await txn.delete(op.entity, where: 'id = ?', whereArgs: [local['id']]);
      // Children die by FK cascade. Their base rows stay marked
      // alive until the peer's own delete ops (or the exporter's
      // base diff, which sees them gone) tombstone them — a child
      // op arriving meanwhile resolves its parent against the
      // live table and quarantines instead of resurrecting.
      await _setShared(
        ctx,
        op.entity,
        op.syncId,
        hash: _deletedHash,
        hlc: op.hlc,
        deleted: true,
      );
      ctx.report.applied++;
      return;
    }
    // Delete vs local edit: later stamp wins; loser preserved.
    final localStamp = (local['updated_hlc'] as String?) ?? '';
    if (op.hlc.compareTo(localStamp) > 0) {
      // The delete wins on stamps for THIS row — but the cascade
      // must still not eat diverged descendants (M4).
      final diverged = await _firstDivergedDescendant(
        ctx,
        op.entity,
        local['id'] as int,
      );
      if (diverged != null) {
        await _recordConflict(
          ctx,
          entity: op.entity,
          rowSyncId: op.syncId,
          kind: 'delete-with-unsynced-children',
          kept: localPayload,
          lostRaw: '(deleted on the other device)',
        );
        ctx.report.keptLocal++;
        return;
      }
      await txn.delete(op.entity, where: 'id = ?', whereArgs: [local['id']]);
      await _recordConflict(
        ctx,
        entity: op.entity,
        rowSyncId: op.syncId,
        kind: 'delete-vs-edit',
        keptRaw: '(deleted on the other device)',
        lost: localPayload,
      );
      await _setShared(
        ctx,
        op.entity,
        op.syncId,
        hash: _deletedHash,
        hlc: op.hlc,
        deleted: true,
      );
      ctx.report.applied++;
    } else {
      await _recordConflict(
        ctx,
        entity: op.entity,
        rowSyncId: op.syncId,
        kind: 'delete-vs-edit',
        kept: localPayload,
        lostRaw: '(deleted on the other device)',
      );
      // Base NOT advanced: the surviving row still has to travel
      // back so the deleter resurrects it (with the conflict copy
      // above explaining why).
      ctx.report.keptLocal++;
    }
  }

  /// Adopt a database that arrived via snapshot RESTORE (Repair
  /// or first pairing, D-011 path) — S7 review S2.
  ///
  /// A restored database file carries the SOURCE device's sync
  /// bookkeeping: its `device_id`, its `sync_base` (which
  /// describes what the SOURCE had shared, with whom), its peer
  /// high-waters and export sequence. Kept as-is, this device
  /// would impersonate the source in package names, diff against
  /// a base that was never this device's shared state, and
  /// silently retire tombstones the restore resurrected rows
  /// against. So the bookkeeping is reset:
  /// - a FRESH device_id (the restored data keeps its row
  ///   sync_ids — identity of DATA is not identity of DEVICE);
  /// - `sync_base`, `sync_peers`, `sync_quarantine` cleared and
  ///   the export sequence/high-waters removed: the next export
  ///   is a full-state package and the next imports re-merge
  ///   from scratch, which converges because row identity is
  ///   stable;
  /// - `sync_ops` is KEPT (op-id dedupe history is harmless and
  ///   prevents re-applying pre-restore packages), as are
  ///   `sync_conflicts` rows (they are content, not bookkeeping).
  ///
  /// What a restore cannot bring back: deletions the source made
  /// AFTER the snapshot was taken. Those rows reappear here —
  /// that is what a snapshot is. The D-011 pre-restore backup is
  /// the recovery for the device being overwritten; the peer's
  /// later delete ops will re-delete on the next exchange only
  /// if the peer re-exports them (its base says it already did),
  /// so after a cross-device repair the owner should treat the
  /// restored state as the truth and let both devices Sync now.
  Future<void> adoptRestoredDatabase() async {
    await _db.transaction((txn) async {
      await txn.delete(
        'sync_meta',
        where: 'key IN (?, ?, ?, ?)',
        whereArgs: [
          'device_id',
          'export_seq',
          'last_export_at',
          'last_export_file',
        ],
      );
      await txn.delete('sync_base');
      await txn.delete('sync_exported');
      await txn.delete('sync_peers');
      await txn.delete('sync_quarantine');
    });
    // Mint the fresh identity outside the transaction
    // (deviceId inserts on its own).
    await AppDatabase.deviceId(_db);
  }

  // ---------------------------------------------------------- status reads

  Future<SyncStatus> status() async {
    final device = await AppDatabase.deviceId(_db);
    final meta = await _db.query('sync_meta');
    final byKey = {
      for (final r in meta) r['key'] as String: r['value'] as String,
    };
    final peers = await _db.query('sync_peers');
    final conflictCount =
        Sqflite.firstIntValue(
          await _db.rawQuery('SELECT COUNT(*) FROM sync_conflicts'),
        ) ??
        0;
    final quarantineCount =
        Sqflite.firstIntValue(
          await _db.rawQuery('SELECT COUNT(*) FROM sync_quarantine'),
        ) ??
        0;
    return SyncStatus(
      deviceId: device,
      lastExportAt: byKey['last_export_at'] == null
          ? null
          : int.tryParse(byKey['last_export_at']!),
      lastExportFile: byKey['last_export_file'],
      peers: [
        for (final r in peers)
          SyncPeerStatus(
            deviceId: r['device_id'] as String,
            lastImportHlc: r['last_import_hlc'] as String?,
            lastImportAt: r['last_import_at'] as int?,
          ),
      ],
      conflictCount: conflictCount,
      quarantineCount: quarantineCount,
    );
  }

  Future<List<SyncConflict>> conflicts() async {
    final rows = await _db.query(
      'sync_conflicts',
      orderBy: 'created_at DESC, id DESC',
    );
    return rows.map(SyncConflict.fromRow).toList();
  }

  Future<List<Map<String, Object?>>> quarantined() async {
    return _db.query('sync_quarantine', orderBy: 'received_at DESC, id DESC');
  }
}

/// Per-import scratch state (one transaction's worth).
class _MergeCtx {
  _MergeCtx(this.txn, this.at, this.report, {this.sourceDevice = ''});

  final Transaction txn;
  final DateTime at;
  final SyncImportReport report;
  final String sourceDevice;

  /// entity → base rows, loaded lazily per transaction.
  final Map<String, Map<String, ({String hash, String hlc, bool deleted})>>
  base = {};

  /// `entity:remoteSyncId` → local row id (identity adoptions).
  final Map<String, int> idMap = {};

  /// Stamp for locally-minted rows during this import.
  String get stampHlc => formatHlc(at.millisecondsSinceEpoch, 0, 'import');
}
