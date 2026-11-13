/// PRJ — project list inside one workspace (S1).
library;

import 'package:flutter/material.dart';

import '../../core/neo_ui.dart';
import '../../core/theme.dart';
import '../items/item_detail_screen.dart';
import '../items/items_screen.dart';
import '../items/link_card/thumbnail_service.dart';
import '../learn/learn_services.dart';
import '../shared_ui.dart';
import '../store.dart';

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({
    super.key,
    required this.store,
    required this.workspace,
    this.learn,
    this.thumbnails,
  });

  final Store store;
  final Workspace workspace;

  /// S4 wiring, forwarded to the items screen (optional).
  final LearnServices? learn;
  final ThumbnailService? thumbnails;

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  late Future<List<Project>> _projects;
  final Set<int> _selectedProjectIds = {};
  bool get _isSelectingProjects => _selectedProjectIds.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _projects = widget.store.projects(widget.workspace.id);
  }

  void _exitSelectionMode() {
    setState(() {
      _selectedProjectIds.clear();
    });
  }

  void _toggleProjectSelection(int id) {
    setState(() {
      if (_selectedProjectIds.contains(id)) {
        _selectedProjectIds.remove(id);
      } else {
        _selectedProjectIds.add(id);
      }
    });
  }

  Future<void> _add() async {
    final name = await promptText(context, title: 'New project');
    if (name == null || name.isEmpty) return;
    await widget.store.createProject(widget.workspace.id, name);
    setState(_reload);
  }

  Future<void> _renameSelectedProject(List<Project> list) async {
    if (_selectedProjectIds.length != 1) return;
    final prj = list.firstWhere((p) => p.id == _selectedProjectIds.first);
    final name = await promptText(
      context,
      title: 'Rename project',
      initial: prj.name,
      label: 'Name',
    );
    if (name == null || name.isEmpty) return;
    await widget.store.renameProject(prj.id, name);
    _exitSelectionMode();
    setState(_reload);
  }

  Future<void> _deleteSelectedProjects(List<Project> list) async {
    final count = _selectedProjectIds.length;
    if (count == 0) return;
    if (!await confirmDelete(
      context,
      '$count project${count > 1 ? 's' : ''}',
      scope: 'Everything inside them is deleted too.',
    )) {
      return;
    }
    for (final id in _selectedProjectIds) {
      await widget.store.deleteProject(id);
    }
    _exitSelectionMode();
    setState(_reload);
  }

  Future<void> _createInstantPage(List<Project> list) async {
    final Project targetProject;
    if (list.isNotEmpty) {
      targetProject = list.first;
    } else {
      targetProject = await widget.store.createProject(
        widget.workspace.id,
        'General',
      );
    }
    final item = await widget.store.createItem(
      targetProject.id,
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

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Project>>(
      future: _projects,
      builder: (context, snapshot) {
        final list = snapshot.data ?? const <Project>[];
        final isSelecting = _isSelectingProjects;

        return PopScope(
          canPop: !isSelecting,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && isSelecting) {
              _exitSelectionMode();
            }
          },
          child: Scaffold(
            appBar: isSelecting
                ? AppBar(
                    leading: IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'Cancel selection',
                      onPressed: _exitSelectionMode,
                    ),
                    title: Text('${_selectedProjectIds.length} selected'),
                    actions: [
                      if (_selectedProjectIds.length == 1)
                        IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          tooltip: 'Rename project',
                          onPressed: () => _renameSelectedProject(list),
                        ),
                      IconButton(
                        icon: Icon(
                          _selectedProjectIds.length == list.length
                              ? Icons.deselect_outlined
                              : Icons.select_all_outlined,
                        ),
                        tooltip: _selectedProjectIds.length == list.length
                            ? 'Deselect all'
                            : 'Select all',
                        onPressed: () {
                          setState(() {
                            if (_selectedProjectIds.length == list.length) {
                              _selectedProjectIds.clear();
                            } else {
                              _selectedProjectIds.addAll(list.map((p) => p.id));
                            }
                          });
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: 'Delete selected projects',
                        onPressed: () => _deleteSelectedProjects(list),
                      ),
                    ],
                  )
                : AppBar(
                    title: Text(widget.workspace.name),
                    actions: [
                      IconButton(
                        icon: const Icon(Icons.edit_note_outlined),
                        tooltip: 'New page',
                        onPressed: () => _createInstantPage(list),
                      ),
                      if (list.isNotEmpty)
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert),
                          tooltip: 'More actions',
                          onSelected: (val) {
                            if (val == 'select_projects') {
                              setState(() {
                                _selectedProjectIds.add(list.first.id);
                              });
                            }
                          },
                          itemBuilder: (ctx) => [
                            const PopupMenuItem(
                              value: 'select_projects',
                              child: Row(
                                children: [
                                  Icon(Icons.checklist_outlined, size: 20),
                                  SizedBox(width: 12),
                                  Text('Select projects'),
                                ],
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
            floatingActionButton: isSelecting
                ? null
                : FloatingActionButton(
                    onPressed: _add,
                    child: const Icon(Icons.add),
                  ),
            body: !snapshot.hasData
                ? const Center(child: CircularProgressIndicator())
                : list.isEmpty
                ? const Center(
                    child: Text(
                      'A clear starting point.\nNo projects yet — '
                      'tap + to create one.',
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(
                      Space.page,
                      Gap.md,
                      Space.page,
                      Gap.lg,
                    ),
                    children: [
                      Column(
                        children: [
                          for (final prj in list)
                            NeoListRow(
                              leading: isSelecting
                                  ? NeoCheck(
                                      done: _selectedProjectIds.contains(
                                        prj.id,
                                      ),
                                    )
                                  : null,
                              icon: isSelecting
                                  ? null
                                  : Icons.folder_open_outlined,
                              title: prj.name,
                              last: prj == list.last,
                              onTap: () {
                                if (isSelecting) {
                                  _toggleProjectSelection(prj.id);
                                } else {
                                  Navigator.push(
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
                                }
                              },
                              onLongPress: () {
                                _toggleProjectSelection(prj.id);
                              },
                            ),
                        ],
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }
}
