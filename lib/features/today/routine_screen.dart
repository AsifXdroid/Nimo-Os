/// TODAY — routine template editor (S2).
/// Templates regenerate as fresh unticked items in each new day's
/// plan (D-002). Changes here affect future days, never past plans.
library;

import 'package:flutter/material.dart';

import '../shared_ui.dart';
import 'today_store.dart';

class RoutineScreen extends StatefulWidget {
  const RoutineScreen({super.key, required this.todayStore});

  final TodayStore todayStore;

  @override
  State<RoutineScreen> createState() => _RoutineScreenState();
}

class _RoutineScreenState extends State<RoutineScreen> {
  late Future<List<PlanTemplate>> _templates;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _templates = widget.todayStore.templates();
  }

  Future<void> _add() async {
    final title =
        await promptText(context, title: 'New routine item', label: 'Title');
    if (title == null || title.isEmpty) return;
    await widget.todayStore.addTemplate(title);
    setState(_reload);
  }

  Future<void> _rename(PlanTemplate t) async {
    final title = await promptText(context,
        title: 'Rename routine item', label: 'Title', initial: t.title);
    if (title == null || title.isEmpty) return;
    await widget.todayStore.renameTemplate(t.id, title);
    setState(_reload);
  }

  Future<void> _delete(PlanTemplate t) async {
    if (!await confirmDelete(context, 'routine item')) return;
    await widget.todayStore.deleteTemplate(t.id);
    setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Routine template')),
      floatingActionButton: FloatingActionButton(
        onPressed: _add,
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder<List<PlanTemplate>>(
        future: _templates,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final list = snapshot.data!;
          if (list.isEmpty) {
            return const Center(
              child: Text(
                  'No routine items yet.\nTap + to add one — it will '
                  'appear in every new day\'s plan.',
                  textAlign: TextAlign.center),
            );
          }
          return ListView.builder(
            itemCount: list.length,
            itemBuilder: (context, i) {
              final t = list[i];
              return ListTile(
                title: Text(t.title),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Switch(
                      value: t.isActive,
                      onChanged: (v) async {
                        await widget.todayStore.setTemplateActive(t.id, v);
                        setState(_reload);
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      tooltip: 'Rename',
                      onPressed: () => _rename(t),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Delete',
                      onPressed: () => _delete(t),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
