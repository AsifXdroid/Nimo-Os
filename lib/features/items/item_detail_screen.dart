/// ITEM — detail/editor for one item (S1: note + checklist).
/// The body switches on the item's registry type; new types add a
/// case here (or their own screen) when they are registered.
library;

import 'package:flutter/material.dart';

import '../shared_ui.dart';
import '../store.dart';

class ItemDetailScreen extends StatefulWidget {
  const ItemDetailScreen({super.key, required this.store, required this.item});

  final Store store;
  final Item item;

  @override
  State<ItemDetailScreen> createState() => _ItemDetailScreenState();
}

class _ItemDetailScreenState extends State<ItemDetailScreen> {
  late final TextEditingController _bodyController;

  @override
  void initState() {
    super.initState();
    _bodyController = TextEditingController(text: widget.item.note ?? '');
  }

  @override
  void dispose() {
    _bodyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return Scaffold(
      appBar: AppBar(title: Text(item.title)),
      body: switch (item.type) {
        ItemType.note => _noteBody(item),
        ItemType.checklist => _ChecklistBody(store: widget.store, item: item),
        _ => const Center(child: Text('Unknown item type')),
      },
    );
  }

  Widget _noteBody(Item item) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Expanded(
            child: TextField(
              controller: _bodyController,
              maxLines: null,
              expands: true,
              decoration: const InputDecoration(
                hintText: 'Write your note…',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () async {
              await widget.store
                  .updateItem(item.id, note: _bodyController.text);
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Saved')),
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

class _ChecklistBody extends StatefulWidget {
  const _ChecklistBody({required this.store, required this.item});

  final Store store;
  final Item item;

  @override
  State<_ChecklistBody> createState() => _ChecklistBodyState();
}

class _ChecklistBodyState extends State<_ChecklistBody> {
  late Future<List<ChecklistEntry>> _entries;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _entries = widget.store.checklistEntries(widget.item.id);
  }

  Future<void> _add() async {
    final text = await promptText(context, title: 'New entry', label: 'Text');
    if (text == null || text.isEmpty) return;
    await widget.store.addChecklistEntry(widget.item.id, text);
    setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: FutureBuilder<List<ChecklistEntry>>(
            future: _entries,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final list = snapshot.data!;
              if (list.isEmpty) {
                return const Center(child: Text('No entries yet.'));
              }
              return ListView.builder(
                itemCount: list.length,
                itemBuilder: (context, i) {
                  final e = list[i];
                  return CheckboxListTile(
                    value: e.isDone,
                    title: Text(
                      e.text,
                      style: e.isDone
                          ? const TextStyle(
                              decoration: TextDecoration.lineThrough)
                          : null,
                    ),
                    secondary: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        await widget.store.deleteChecklistEntry(e.id);
                        setState(_reload);
                      },
                    ),
                    onChanged: (v) async {
                      await widget.store
                          .setChecklistEntryDone(e.id, v ?? false);
                      setState(_reload);
                    },
                  );
                },
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: _add,
            icon: const Icon(Icons.add),
            label: const Text('Add entry'),
          ),
        ),
      ],
    );
  }
}
