/// ITEM — item list inside one project (S1).
/// Rendering and creation are driven by the item-type registry.
library;

import 'package:flutter/material.dart';

import '../shared_ui.dart';
import '../store.dart';
import 'item_detail_screen.dart';
import 'item_registry.dart';

class ItemsScreen extends StatefulWidget {
  const ItemsScreen({super.key, required this.store, required this.project});

  final Store store;
  final Project project;

  @override
  State<ItemsScreen> createState() => _ItemsScreenState();
}

class _ItemsScreenState extends State<ItemsScreen> {
  late Future<List<Item>> _items;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _items = widget.store.items(widget.project.id);
  }

  Future<void> _add() async {
    final def = await showModalBottomSheet<ItemTypeDef>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('Add item')),
            for (final t in itemTypes)
              ListTile(
                leading: Icon(t.icon),
                title: Text(t.label),
                onTap: () => Navigator.pop(context, t),
              ),
          ],
        ),
      ),
    );
    if (def == null || !mounted) return;
    final title = await promptText(context,
        title: 'New ${def.label.toLowerCase()}', label: 'Title');
    if (title == null || title.isEmpty) return;
    final item = await widget.store.createItem(
      widget.project.id,
      type: def.key,
      title: title,
    );
    setState(_reload);
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ItemDetailScreen(store: widget.store, item: item),
      ),
    );
    setState(_reload);
  }

  Future<void> _delete(Item item) async {
    if (!await confirmDelete(context, 'item')) return;
    await widget.store.deleteItem(item.id);
    setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.project.name)),
      floatingActionButton: FloatingActionButton(
        onPressed: _add,
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder<List<Item>>(
        future: _items,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final list = snapshot.data!;
          if (list.isEmpty) {
            return const Center(
              child: Text('No items yet.\nTap + to add a note or checklist.',
                  textAlign: TextAlign.center),
            );
          }
          return ListView.builder(
            itemCount: list.length,
            itemBuilder: (context, i) {
              final item = list[i];
              final def = itemTypeDef(item.type);
              return ListTile(
                leading: Icon(def.icon),
                title: Text(item.title),
                subtitle: Text(def.label),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _delete(item),
                ),
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          ItemDetailScreen(store: widget.store, item: item),
                    ),
                  );
                  setState(_reload);
                },
              );
            },
          );
        },
      ),
    );
  }
}
