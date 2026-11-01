/// Data layer for WS / PRJ / ITEM (S1).
///
/// One small store class wrapping the database: all SQL for
/// workspaces, projects, items, and checklist entries lives here so
/// features never write raw queries in UI code. UI talks to [Store];
/// [Store] talks to SQLite.
library;

import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../core/db/app_database.dart';

// ---------------------------------------------------------------- WS

class Workspace {
  Workspace({
    required this.id,
    required this.name,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
    this.pinned = false,
  });

  final int id;
  final String name;
  final int sortOrder;
  final int createdAt;
  final int updatedAt;

  /// Pinned to the Home screen (S2, schema v2).
  final bool pinned;

  factory Workspace.fromRow(Map<String, Object?> r) => Workspace(
        id: r['id'] as int,
        name: r['name'] as String,
        sortOrder: r['sort_order'] as int,
        createdAt: r['created_at'] as int,
        updatedAt: r['updated_at'] as int,
        pinned: (r['pinned'] as int? ?? 0) == 1,
      );
}

/// An item plus the names of its project and workspace (Home's
/// "recent items" list, S2).
class RecentItem {
  RecentItem({
    required this.item,
    required this.projectName,
    required this.workspaceName,
  });

  final Item item;
  final String projectName;
  final String workspaceName;
}

// ---------------------------------------------------------------- PRJ

class Project {
  Project({
    required this.id,
    required this.workspaceId,
    required this.name,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final int workspaceId;
  final String name;
  final int sortOrder;
  final int createdAt;
  final int updatedAt;

  factory Project.fromRow(Map<String, Object?> r) => Project(
        id: r['id'] as int,
        workspaceId: r['workspace_id'] as int,
        name: r['name'] as String,
        sortOrder: r['sort_order'] as int,
        createdAt: r['created_at'] as int,
        updatedAt: r['updated_at'] as int,
      );
}

// ---------------------------------------------------------------- ITEM

/// Item type keys — the registry keys of FEATURE_MAP's item-type table.
abstract final class ItemType {
  static const String note = 'note';
  static const String checklist = 'checklist';
  static const String linkCard = 'link_card';
  static const String htmlQuiz = 'html_quiz';
}

class Item {
  Item({
    required this.id,
    required this.projectId,
    required this.type,
    required this.title,
    required this.note,
    required this.payload,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
    this.updatedHlc,
  });

  final int id;
  final int projectId;
  final String type;
  final String title;
  final String? note;

  /// Decoded JSON payload (shape per type, see DATA_MODEL.md), or null.
  final Map<String, Object?>? payload;
  final int sortOrder;
  final int createdAt;
  final int updatedAt;

  /// The row's sync stamp, when the query carried it. Local
  /// store writes never move it; a remote sync apply does —
  /// which is what makes concurrent-edit detection possible
  /// (see item_detail_screen.dart).
  final String? updatedHlc;

  factory Item.fromRow(Map<String, Object?> r) => Item(
        id: r['id'] as int,
        projectId: r['project_id'] as int,
        type: r['type'] as String,
        title: r['title'] as String,
        note: r['note'] as String?,
        payload: r['payload'] == null
            ? null
            : (jsonDecode(r['payload'] as String) as Map)
                .cast<String, Object?>(),
        sortOrder: r['sort_order'] as int,
        createdAt: r['created_at'] as int,
        updatedAt: r['updated_at'] as int,
        updatedHlc: r['updated_hlc'] as String?,
      );
}

class ChecklistEntry {
  ChecklistEntry({
    required this.id,
    required this.itemId,
    required this.text,
    required this.isDone,
    required this.sortOrder,
  });

  final int id;
  final int itemId;
  final String text;
  final bool isDone;
  final int sortOrder;

  factory ChecklistEntry.fromRow(Map<String, Object?> r) => ChecklistEntry(
        id: r['id'] as int,
        itemId: r['item_id'] as int,
        text: r['text'] as String,
        isDone: (r['is_done'] as int) == 1,
        sortOrder: r['sort_order'] as int,
      );
}

// ---------------------------------------------------------------- Store

class Store {
  Store(this._db);

  final Database _db;

  // --- workspaces ---
  Future<List<Workspace>> workspaces() async {
    final rows = await _db.query('workspaces',
        orderBy: 'sort_order ASC, id ASC');
    return rows.map(Workspace.fromRow).toList();
  }

  Future<Workspace> createWorkspace(String name) async {
    final now = AppDatabase.nowMs();
    final id = await _db.insert('workspaces', {
      'name': name,
      'sort_order': (await _maxSort('workspaces')) + 1,
      'created_at': now,
      'updated_at': now,
    });
    return (await _db.query('workspaces', where: 'id = ?', whereArgs: [id]))
        .map(Workspace.fromRow)
        .single;
  }

  Future<void> renameWorkspace(int id, String name) async {
    await _db.update(
      'workspaces',
      {'name': name, 'updated_at': AppDatabase.nowMs()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteWorkspace(int id) async {
    await _db.delete('workspaces', where: 'id = ?', whereArgs: [id]);
  }

  // --- pinned workspaces & Home queries (S2) ---
  Future<void> setWorkspacePinned(int id, bool pinned) async {
    await _db.update('workspaces', {'pinned': pinned ? 1 : 0},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Workspace>> pinnedWorkspaces() async {
    final rows = await _db.query('workspaces',
        where: 'pinned = 1', orderBy: 'sort_order ASC, id ASC');
    return rows.map(Workspace.fromRow).toList();
  }

  Future<int> itemCountForWorkspace(int workspaceId) async {
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS c FROM items i '
      'JOIN projects p ON p.id = i.project_id '
      'WHERE p.workspace_id = ?',
      [workspaceId],
    );
    return rows.single['c'] as int;
  }

  /// Latest items across all projects, newest activity first.
  Future<List<RecentItem>> recentItems({int limit = 5}) async {
    final rows = await _db.rawQuery(
      'SELECT i.*, p.name AS project_name, w.name AS workspace_name '
      'FROM items i '
      'JOIN projects p ON p.id = i.project_id '
      'JOIN workspaces w ON w.id = p.workspace_id '
      'ORDER BY i.updated_at DESC, i.id DESC LIMIT ?',
      [limit],
    );
    return rows
        .map((r) => RecentItem(
              item: Item.fromRow(r),
              projectName: r['project_name'] as String,
              workspaceName: r['workspace_name'] as String,
            ))
        .toList();
  }

  // --- projects ---
  Future<List<Project>> projects(int workspaceId) async {
    final rows = await _db.query('projects',
        where: 'workspace_id = ?',
        whereArgs: [workspaceId],
        orderBy: 'sort_order ASC, id ASC');
    return rows.map(Project.fromRow).toList();
  }

  Future<Project> createProject(int workspaceId, String name) async {
    final now = AppDatabase.nowMs();
    final id = await _db.insert('projects', {
      'workspace_id': workspaceId,
      'name': name,
      'sort_order': (await _maxSort('projects',
              where: 'workspace_id = ?', whereArgs: [workspaceId])) +
          1,
      'created_at': now,
      'updated_at': now,
    });
    return (await _db.query('projects', where: 'id = ?', whereArgs: [id]))
        .map(Project.fromRow)
        .single;
  }

  Future<void> renameProject(int id, String name) async {
    await _db.update(
      'projects',
      {'name': name, 'updated_at': AppDatabase.nowMs()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteProject(int id) async {
    await _db.delete('projects', where: 'id = ?', whereArgs: [id]);
  }

  // --- items ---
  Future<List<Item>> items(int projectId) async {
    final rows = await _db.query('items',
        where: 'project_id = ?',
        whereArgs: [projectId],
        orderBy: 'sort_order ASC, id ASC');
    return rows.map(Item.fromRow).toList();
  }

  Future<Item> createItem(
    int projectId, {
    required String type,
    required String title,
    String? note,
    Map<String, Object?>? payload,
  }) async {
    final now = AppDatabase.nowMs();
    final id = await _db.insert('items', {
      'project_id': projectId,
      'type': type,
      'title': title,
      'note': note,
      'payload': payload == null ? null : jsonEncode(payload),
      'sort_order': (await _maxSort('items',
              where: 'project_id = ?', whereArgs: [projectId])) +
          1,
      'created_at': now,
      'updated_at': now,
    });
    return (await _db.query('items', where: 'id = ?', whereArgs: [id]))
        .map(Item.fromRow)
        .single;
  }

  Future<void> updateItem(int id, {String? title, String? note}) async {
    final values = <String, Object?>{'updated_at': AppDatabase.nowMs()};
    if (title != null) values['title'] = title;
    if (note != null) values['note'] = note;
    await _db.update('items', values, where: 'id = ?', whereArgs: [id]);
  }

  /// Replace an item's JSON payload (link_card topic link and
  /// thumbnail name are written this way after creation, S4).
  Future<void> updateItemPayload(int id, Map<String, Object?> payload) async {
    await _db.update(
      'items',
      {'payload': jsonEncode(payload), 'updated_at': AppDatabase.nowMs()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<Item> itemById(int id) async {
    final rows =
        await _db.query('items', where: 'id = ?', whereArgs: [id], limit: 1);
    return Item.fromRow(rows.single);
  }

  Future<void> deleteItem(int id) async {
    await _db.delete('items', where: 'id = ?', whereArgs: [id]);
  }

  // --- checklist entries ---
  Future<List<ChecklistEntry>> checklistEntries(int itemId) async {
    final rows = await _db.query('checklist_entries',
        where: 'item_id = ?',
        whereArgs: [itemId],
        orderBy: 'sort_order ASC, id ASC');
    return rows.map(ChecklistEntry.fromRow).toList();
  }

  Future<ChecklistEntry> addChecklistEntry(int itemId, String text) async {
    final id = await _db.insert('checklist_entries', {
      'item_id': itemId,
      'text': text,
      'is_done': 0,
      'sort_order': (await _maxSort('checklist_entries',
              where: 'item_id = ?', whereArgs: [itemId])) +
          1,
    });
    return (await _db
            .query('checklist_entries', where: 'id = ?', whereArgs: [id]))
        .map(ChecklistEntry.fromRow)
        .single;
  }

  Future<void> setChecklistEntryDone(int id, bool done) async {
    await _db.update('checklist_entries', {'is_done': done ? 1 : 0},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteChecklistEntry(int id) async {
    await _db.delete('checklist_entries', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> _maxSort(String table, {String? where, List<Object?>? whereArgs}) async {
    final rows = await _db.query(table,
        columns: ['MAX(sort_order) AS m'], where: where, whereArgs: whereArgs);
    return (rows.single['m'] as int?) ?? -1;
  }
}
