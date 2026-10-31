/// SPACES — the Neo workbench (D-037): workspace cards on top,
/// the selected workspace's projects as in-page accordions with
/// their items inside (the prototype's depth cut — an item is
/// one tap from this page), and recently touched items below.
/// The classic ProjectsScreen route still exists (Home's pinned
/// spaces and project management open it).
library;

import 'package:flutter/material.dart';

import '../../core/motion.dart';
import '../../core/neo_ui.dart';
import '../../core/theme.dart';
import '../items/item_detail_screen.dart';
import '../items/item_registry.dart';
import '../items/items_screen.dart';
import '../items/link_card/thumbnail_service.dart';
import '../learn/learn_services.dart';
import '../projects/projects_screen.dart';
import '../shared_ui.dart';
import '../store.dart';

/// Everything the Spaces page renders, loaded in one pass.
class _SpacesData {
  const _SpacesData({
    required this.workspaces,
    required this.counts,
    required this.recent,
  });

  final List<Workspace> workspaces;

  /// workspaceId → (project count, item count) for the cards.
  final Map<int, ({int projects, int items})> counts;
  final List<RecentItem> recent;
}

class WorkspacesScreen extends StatefulWidget {
  const WorkspacesScreen({
    super.key,
    required this.store,
    this.learn,
    this.thumbnails,
  });

  final Store store;

  /// S4 wiring, forwarded to project/item screens (optional).
  final LearnServices? learn;
  final ThumbnailService? thumbnails;

  @override
  State<WorkspacesScreen> createState() => _WorkspacesScreenState();
}

class _WorkspacesScreenState extends State<WorkspacesScreen> {
  late Future<_SpacesData> _data;
  int? _selectedId;
  Future<List<({Project project, List<Item> items})>>? _selection;
  final Set<int> _expanded = {};

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _data = _load();
  }

  Future<_SpacesData> _load() async {
    final workspaces = await widget.store.workspaces();
    final counts = <int, ({int projects, int items})>{};
    for (final ws in workspaces) {
      counts[ws.id] = (
        projects: (await widget.store.projects(ws.id)).length,
        items: await widget.store.itemCountForWorkspace(ws.id),
      );
    }
    final recent = await widget.store.recentItems(limit: 5);
    if (workspaces.isNotEmpty &&
        !workspaces.any((w) => w.id == _selectedId)) {
      _selectedId = workspaces.first.id;
      _selection = _loadSelection(workspaces.first.id);
    }
    return _SpacesData(
        workspaces: workspaces, counts: counts, recent: recent);
  }

  Future<List<({Project project, List<Item> items})>>
      _loadSelection(int workspaceId) async {
    final projects = await widget.store.projects(workspaceId);
    final result = <({Project project, List<Item> items})>[];
    for (final prj in projects) {
      result.add(
          (project: prj, items: await widget.store.items(prj.id)));
    }
    if (result.isNotEmpty && _expanded.isEmpty) {
      _expanded.add(result.first.project.id);
    }
    return result;
  }

  void _select(Workspace ws) {
    if (ws.id == _selectedId) return;
    setState(() {
      _selectedId = ws.id;
      _expanded.clear();
      _selection = _loadSelection(ws.id);
    });
  }

  Future<void> _openItem(Item item) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ItemDetailScreen(
          store: widget.store,
          item: item,
          learn: widget.learn,
          thumbnails: widget.thumbnails,
        ),
      ),
    );
    if (!mounted) return;
    setState(() {
      _reload();
      if (_selectedId != null) {
        _selection = _loadSelection(_selectedId!);
      }
    });
  }

  Future<void> _newProject(Workspace ws) async {
    final name = await promptText(context, title: 'New project');
    if (name == null || name.isEmpty) return;
    await widget.store.createProject(ws.id, name);
    if (!mounted) return;
    setState(() {
      _reload();
      _selection = _loadSelection(ws.id);
    });
  }

  Future<void> _add() async {
    final name = await promptText(context, title: 'New workspace');
    if (name == null || name.isEmpty) return;
    await widget.store.createWorkspace(name);
    setState(_reload);
  }

  Future<void> _menu(Workspace ws) async {
    final action = await showRowMenu(context);
    if (!mounted || action == null) return;
    switch (action) {
      case RowAction.rename:
        final name = await promptText(context,
            title: 'Rename workspace', initial: ws.name);
        if (name == null || name.isEmpty) return;
        await widget.store.renameWorkspace(ws.id, name);
      case RowAction.delete:
        if (!await confirmDelete(context, 'workspace')) return;
        await widget.store.deleteWorkspace(ws.id);
    }
    setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<_SpacesData>(
        future: _data,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Padding(
              padding: EdgeInsets.fromLTRB(
                  Space.page, Gap.md, Space.page, Gap.lg),
              child: DelayedSkeleton(skeleton: SkeletonList(panels: 2)),
            );
          }
          final data = snapshot.data!;
          Workspace? selected;
          for (final w in data.workspaces) {
            if (w.id == _selectedId) selected = w;
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(
                Space.page, Gap.md, Space.page, Gap.lg),
            children: [
              const NeoPageTitle(
                eyebrow: 'Your personal workbench',
                heading: 'Spaces to think and make.',
                sub: 'Keep the things you’re building close.',
              ),
              const SizedBox(height: Gap.lg),
              NeoSectionHead(
                title: 'Your spaces',
                actionLabel: '+ New space',
                onAction: _add,
              ),
              const SizedBox(height: Space.s3),
              if (data.workspaces.isEmpty)
                Text(
                  'A clear starting point. No workspaces yet — '
                  'create one to begin.',
                  style: Theme.of(context).textTheme.bodyMedium,
                )
              else
                // D-039: spaces are the concept's hairline ROWS
                // with serif glyph squares — not a tile grid.
                Column(
                  children: [
                    for (final ws in data.workspaces)
                      _spaceRow(
                        context,
                        ws,
                        data,
                        selected: ws.id == _selectedId,
                        last: ws == data.workspaces.last,
                      ),
                  ],
                ),
              if (selected != null) ...[
                const SizedBox(height: Gap.lg),
                _selectedPanel(context, selected),
              ],
              if (data.recent.isNotEmpty) ...[
                const SizedBox(height: Gap.lg),
                const NeoSectionHead(title: 'Recently touched'),
                const SizedBox(height: Space.s3),
                Column(
                  children: [
                    for (final r in data.recent)
                      NeoListRow(
                        icon: itemTypeDef(r.item.type).icon,
                        title: r.item.title,
                        sub: '${r.workspaceName} · ${r.projectName}',
                        last: r == data.recent.last,
                        onTap: () => _openItem(r.item),
                      ),
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  /// One space as an editorial row: a bordered square with
  /// the space's serif initial, its name and counts, and a
  /// chevron. Selected = the glyph square fills with the
  /// container tint and a mint edge (the detail panel below
  /// carries the selection's actions).
  Widget _spaceRow(
    BuildContext context,
    Workspace ws,
    _SpacesData data, {
    required bool selected,
    required bool last,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final counts = data.counts[ws.id] ?? (projects: 0, items: 0);
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: last
              ? BorderSide.none
              : BorderSide(color: scheme.outlineVariant),
        ),
      ),
      child: InkWell(
        onTap: () => _select(ws),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.s4),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: selected
                      ? scheme.primaryContainer
                      : scheme.surface,
                  border: Border.all(
                    color: selected ? scheme.primary : scheme.outline,
                  ),
                  borderRadius: BorderRadius.circular(RadiusToken.sm),
                ),
                alignment: Alignment.center,
                child: Text(
                  ws.name.isEmpty ? '?' : ws.name[0].toUpperCase(),
                  style: TextStyle(
                    fontFamily: fontSerif,
                    fontFamilyFallback: fontSerifFallback,
                    fontSize: 20,
                    color: selected
                        ? scheme.onPrimaryContainer
                        : scheme.primary,
                  ),
                ),
              ),
              const SizedBox(width: Space.s4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ws.name,
                      style: theme.textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${counts.projects} projects · ${counts.items} items'
                      '${ws.pinned ? ' · pinned' : ''}',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  size: 20, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  Widget _selectedPanel(BuildContext context, Workspace ws) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return NeoPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(ws.name, style: theme.textTheme.titleMedium),
              ),
              IconButton(
                icon: Icon(
                    ws.pinned ? Icons.push_pin : Icons.push_pin_outlined),
                tooltip: ws.pinned ? 'Unpin from Home' : 'Pin to Home',
                onPressed: () async {
                  await widget.store.setWorkspacePinned(ws.id, !ws.pinned);
                  setState(_reload);
                },
              ),
              IconButton(
                icon: const Icon(Icons.more_vert),
                onPressed: () => _menu(ws),
              ),
            ],
          ),
          Text(
            'Workspace → project → item. Open a project to see '
            'what’s inside.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: Space.s3),
          FutureBuilder<List<({Project project, List<Item> items})>>(
            future: _selection,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: Space.s4),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final entries = snapshot.data!;
              if (entries.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: Space.s3),
                  child: Text(
                    'A clear starting point. No projects in this '
                    'space yet.',
                    style: theme.textTheme.bodyMedium,
                  ),
                );
              }
              return Column(
                children: [
                  for (final e in entries)
                    _projectAccordion(context, e,
                        last: e == entries.last),
                ],
              );
            },
          ),
          const SizedBox(height: Space.s3),
          Wrap(
            spacing: Space.s2,
            children: [
              TextButton(
                onPressed: () => _newProject(ws),
                child: const Text('+ New project'),
              ),
              TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProjectsScreen(
                      store: widget.store,
                      workspace: ws,
                      learn: widget.learn,
                      thumbnails: widget.thumbnails,
                    ),
                  ),
                ),
                child: const Text('All projects →'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _projectAccordion(
    BuildContext context,
    ({Project project, List<Item> items}) entry, {
    bool last = false,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final prj = entry.project;
    final expanded = _expanded.contains(prj.id);
    return Container(
      decoration: last
          ? null
          : BoxDecoration(
              border: Border(
                bottom: BorderSide(color: scheme.outlineVariant),
              ),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() {
              if (expanded) {
                _expanded.remove(prj.id);
              } else {
                _expanded.add(prj.id);
              }
            }),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.s4),
              child: Row(
                children: [
                  Icon(Icons.folder_open_outlined,
                      size: 20, color: scheme.primary),
                  const SizedBox(width: Space.s3),
                  Expanded(
                    child: Text(
                      prj.name,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(
                    '${entry.items.length} items',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(width: Space.s2),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (expanded) ...[
            if (entry.items.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.s3),
                child: Text(
                  'A clear starting point. No items in this '
                  'project yet.',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            for (final item in entry.items)
              NeoListRow(
                icon: itemTypeDef(item.type).icon,
                title: item.title,
                sub: itemTypeDef(item.type).label,
                last: item == entry.items.last,
                onTap: () => _openItem(item),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ItemsScreen(
                        store: widget.store,
                        project: prj,
                        learn: widget.learn,
                        thumbnails: widget.thumbnails,
                      ),
                    ),
                  );
                  if (!mounted) return;
                  setState(() {
                    _reload();
                    _selection = _loadSelection(prj.workspaceId);
                  });
                },
                child: const Text('Manage project →'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
