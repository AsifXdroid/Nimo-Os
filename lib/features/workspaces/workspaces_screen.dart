/// SPACES — the landing (Spaces & Notebook brief,
/// 2026-11-01): a simple place to find and open work.
///
/// A compact header, the workspace list (tap opens the
/// workspace's own screen), and Recent Projects from REAL
/// visit history (recorded when a project opens — never
/// derived from edits). No expanded panels, no accordions,
/// no dashboard counts: Spaces → Workspace → Project → Page
/// is plain click-to-open navigation.
library;

import 'package:flutter/material.dart';

import '../../core/motion.dart';
import '../../core/neo_ui.dart';
import '../../core/spatial_ui.dart';
import '../../core/theme.dart';
import '../items/item_detail_screen.dart';
import '../items/items_screen.dart';
import '../items/link_card/thumbnail_service.dart';
import '../learn/learn_services.dart';
import '../projects/projects_screen.dart';
import '../shared_ui.dart';
import '../store.dart';
import 'recent_projects.dart';

/// Everything the landing renders, loaded in one pass.
class _SpacesData {
  const _SpacesData({
    required this.workspaces,
    required this.recents,
    required this.inboxCount,
    this.workspaceProjectCounts = const {},
  });

  final List<Workspace> workspaces;

  /// Visited projects, resolved against live rows (stale
  /// sync ids dropped), most recent first, display-capped.
  final List<({Project project, String workspaceName})> recents;

  /// Total count of items/notes currently in the Inbox.
  final int inboxCount;

  /// Project count per workspace for clear overview.
  final Map<int, int> workspaceProjectCounts;
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
    final inboxCount = await widget.store.inboxItemCount();
    final visits = await widget.store.recentProjectVisits();
    final recents = <({Project project, String workspaceName})>[];
    final counts = <int, int>{};
    if (workspaces.isNotEmpty) {
      final bySyncId = <String, ({Project project, String workspaceName})>{};
      for (final ws in workspaces) {
        final prjs = await widget.store.projects(ws.id);
        counts[ws.id] = prjs.length;
        if (visits.isNotEmpty) {
          for (final prj in prjs) {
            final sid = prj.syncId;
            if (sid != null) {
              bySyncId[sid] = (project: prj, workspaceName: ws.name);
            }
          }
        }
      }
      for (final v in visits) {
        final hit = bySyncId[v.syncId];
        if (hit != null) {
          recents.add(hit);
          if (recents.length >= RecentProjects.maxShown) break;
        }
      }
    }
    return _SpacesData(
      workspaces: workspaces,
      recents: recents,
      inboxCount: inboxCount,
      workspaceProjectCounts: counts,
    );
  }

  Future<void> _openInbox() async {
    final inbox = await widget.store.ensureInboxProject();
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ItemsScreen(
          store: widget.store,
          project: inbox,
          learn: widget.learn,
          thumbnails: widget.thumbnails,
        ),
      ),
    );
    if (!mounted) return;
    setState(_reload);
  }

  Future<void> _createInstantPage() async {
    final inbox = await widget.store.ensureInboxProject();
    final item = await widget.store.createItem(
      inbox.id,
      type: ItemType.note,
      title: '',
    );
    if (!mounted) return;
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
    setState(_reload);
  }

  Future<void> _openWorkspace(Workspace ws) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProjectsScreen(
          store: widget.store,
          workspace: ws,
          learn: widget.learn,
          thumbnails: widget.thumbnails,
        ),
      ),
    );
    if (!mounted) return;
    setState(_reload);
  }

  Future<void> _openProject(Project prj) async {
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
    setState(_reload);
  }

  Future<void> _add() async {
    final name = await promptText(context, title: 'New workspace');
    if (name == null || name.isEmpty) return;
    await widget.store.createWorkspace(name);
    setState(_reload);
  }

  /// Every workspace management action the old expanded
  /// panel carried, on long-press: rename, pin/unpin, delete.
  Future<void> _workspaceActions(Workspace ws) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Rename'),
              onTap: () => Navigator.pop(context, 'rename'),
            ),
            ListTile(
              leading: Icon(
                  ws.pinned ? Icons.push_pin : Icons.push_pin_outlined),
              title: Text(ws.pinned ? 'Unpin from Home' : 'Pin to Home'),
              onTap: () => Navigator.pop(context, 'pin'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'rename':
        final name = await promptText(context,
            title: 'Rename workspace', initial: ws.name);
        if (name == null || name.isEmpty) return;
        await widget.store.renameWorkspace(ws.id, name);
      case 'pin':
        await widget.store.setWorkspacePinned(ws.id, !ws.pinned);
      case 'delete':
        if (!await confirmDelete(context, 'workspace')) return;
        await widget.store.deleteWorkspace(ws.id);
    }
    setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      body: PageTop(
        child: FutureBuilder<_SpacesData>(
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
            // D-052: solid canvas (glass atmosphere retired).
            return ListView(
                padding: const EdgeInsets.fromLTRB(
                    Space.page, Gap.md, Space.page, 110.0),
                children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            // D-052: the prototype's eyebrow for
                            // this destination.
                            'YOUR PRIVATE SPACE',
                            style: AppType.eyebrow.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: Space.s2),
                          Text(
                            // D-052: the prototype's name for this
                            // destination + its line. (The theme's
                            // headline is sans now — no serif
                            // override.)
                            'Organise',
                            style: theme.textTheme.headlineSmall,
                          ),
                          const SizedBox(height: Gap.sm),
                          Text(
                            'Everything has a place.',
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: Space.s2),
                    FilledButton.tonalIcon(
                      onPressed: _createInstantPage,
                      icon: const Icon(Icons.edit_note_outlined, size: 18),
                      label: const Text('New page'),
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Gap.lg),
                _inboxCard(context, data.inboxCount),
                NeoSectionHead(
                  title: 'Your spaces',
                  actionLabel: '+ New space',
                  onAction: _add,
                ),
                const SizedBox(height: Space.s3),
                if (data.workspaces.isEmpty)
                  Text(
                    'No workspaces yet — create one to begin.',
                    style: theme.textTheme.bodyMedium,
                  )
                else
                  Column(
                    children: [
                      for (final ws in data.workspaces)
                        _spaceRow(
                          context,
                          ws,
                          last: ws == data.workspaces.last,
                          projectCount: data.workspaceProjectCounts[ws.id] ?? 0,
                        ),
                    ],
                  ),
                if (data.recents.isNotEmpty) ...[
                  const SizedBox(height: Gap.lg),
                  const NeoSectionHead(title: 'Recent projects'),
                  const SizedBox(height: Space.s3),
                  Column(
                    children: [
                      for (final r in data.recents)
                        NeoListRow(
                          icon: Icons.folder_open_outlined,
                          title: r.project.name,
                          sub: r.workspaceName,
                          last: r == data.recents.last,
                          onTap: () => _openProject(r.project),
                        ),
                    ],
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  /// One space as a quiet row: serif initial square, name,
  /// project count, and chevron. Tap opens the workspace; long-press manages it.
  Widget _spaceRow(BuildContext context, Workspace ws,
      {required bool last, int projectCount = 0}) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final projectText =
        projectCount == 1 ? '1 project' : '$projectCount projects';
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: last
              ? BorderSide.none
              : BorderSide(color: scheme.outlineVariant),
        ),
      ),
      child: InkWell(
        onTap: () => _openWorkspace(ws),
        onLongPress: () => _workspaceActions(ws),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.s4),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  border: Border.all(color: scheme.outline),
                  borderRadius: BorderRadius.circular(RadiusToken.control),
                ),
                alignment: Alignment.center,
                child: Text(
                  ws.name.isEmpty ? '?' : ws.name[0].toUpperCase(),
                  style: TextStyle(
                    // D-052: sans initial (serif retired).
                    fontFamily: fontSans,
                    fontFamilyFallback: fontSansFallback,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: scheme.primary,
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
                    const SizedBox(height: Space.s1),
                    Text(
                      projectText,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (ws.pinned)
                Icon(Icons.push_pin_outlined,
                    size: 16, color: scheme.onSurfaceVariant),
              Icon(Icons.chevron_right,
                  size: 20, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  /// Prominent, discoverable Inbox card at the top of Spaces.
  Widget _inboxCard(BuildContext context, int count) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final countText = count == 1 ? '1 item' : '$count items';

    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.lg),
      child: SpatialCard(
        elevation: SpatialDepth.elevated,
        borderRadius: RadiusToken.card,
        padding: EdgeInsets.zero,
        enablePerspective: true,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: const ValueKey('spaces_inbox_card'),
            onTap: _openInbox,
            borderRadius: BorderRadius.circular(RadiusToken.card),
            child: Container(
              padding: const EdgeInsets.all(Space.s4),
              child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(RadiusToken.control),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.inbox_outlined,
                    color: scheme.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: Space.s4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Inbox',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: Space.s1),
                      Text(
                        'Quick captures and incoming notes',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Space.s3,
                    vertical: Space.s1,
                  ),
                  decoration: BoxDecoration(
                    color: count > 0
                        ? scheme.surfaceContainerHigh
                        : scheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(RadiusToken.round),
                  ),
                  child: Text(
                    countText,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: count > 0
                          ? scheme.onSurface
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: Space.s2),
                Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
}
