/// WS — workspace list (S1). Tap a workspace to open its projects.
library;

import 'package:flutter/material.dart';

import '../projects/projects_screen.dart';
import '../shared_ui.dart';
import '../store.dart';

class WorkspacesScreen extends StatefulWidget {
  const WorkspacesScreen({super.key, required this.store});

  final Store store;

  @override
  State<WorkspacesScreen> createState() => _WorkspacesScreenState();
}

class _WorkspacesScreenState extends State<WorkspacesScreen> {
  late Future<List<Workspace>> _workspaces;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _workspaces = widget.store.workspaces();
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
      appBar: AppBar(title: const Text('Workspaces')),
      floatingActionButton: FloatingActionButton(
        onPressed: _add,
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder<List<Workspace>>(
        future: _workspaces,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final list = snapshot.data!;
          if (list.isEmpty) {
            return const Center(
              child: Text('No workspaces yet.\nTap + to create one.',
                  textAlign: TextAlign.center),
            );
          }
          return ListView.builder(
            itemCount: list.length,
            itemBuilder: (context, i) {
              final ws = list[i];
              return ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(ws.name),
                trailing: IconButton(
                  icon: const Icon(Icons.more_vert),
                  onPressed: () => _menu(ws),
                ),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        ProjectsScreen(store: widget.store, workspace: ws),
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
