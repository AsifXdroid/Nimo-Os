/// PRJ — project list inside one workspace (S1).
library;

import 'package:flutter/material.dart';

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

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _projects = widget.store.projects(widget.workspace.id);
  }

  Future<void> _add() async {
    final name = await promptText(context, title: 'New project');
    if (name == null || name.isEmpty) return;
    await widget.store.createProject(widget.workspace.id, name);
    setState(_reload);
  }

  Future<void> _menu(Project prj) async {
    final action = await showRowMenu(context);
    if (!mounted || action == null) return;
    switch (action) {
      case RowAction.rename:
        final name = await promptText(context,
            title: 'Rename project', initial: prj.name);
        if (name == null || name.isEmpty) return;
        await widget.store.renameProject(prj.id, name);
      case RowAction.delete:
        if (!await confirmDelete(context, 'project')) return;
        await widget.store.deleteProject(prj.id);
    }
    setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.workspace.name)),
      floatingActionButton: FloatingActionButton(
        onPressed: _add,
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder<List<Project>>(
        future: _projects,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final list = snapshot.data!;
          if (list.isEmpty) {
            return const Center(
              child: Text('No projects yet.\nTap + to create one.',
                  textAlign: TextAlign.center),
            );
          }
          return ListView.builder(
            itemCount: list.length,
            itemBuilder: (context, i) {
              final prj = list[i];
              return ListTile(
                leading: const Icon(Icons.folder_open_outlined),
                title: Text(prj.name),
                trailing: IconButton(
                  icon: const Icon(Icons.more_vert),
                  onPressed: () => _menu(prj),
                ),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ItemsScreen(
                      store: widget.store,
                      project: prj,
                      learn: widget.learn,
                      thumbnails: widget.thumbnails,
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
