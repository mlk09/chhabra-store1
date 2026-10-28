import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/app_state.dart';
import '../../core/i18n.dart';
import '../../core/widgets/common.dart';
import '../../data/models/catalog.dart';
import '../../data/models/category.dart';

const _icons = [
  '🌾',
  '🫙',
  '🌶️',
  '🧂',
  '🥛',
  '🥬',
  '🍎',
  '🍪',
  '☕',
  '🧴',
  '🧹',
  '🍞',
  '🥚',
  '🧈',
  '🍫',
  '🧃',
  '🍚',
  '🫘',
  '🧼',
  '👶',
  '🐶',
  '🪔',
  '🛍️',
  '❄️',
];

class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(catalogProvider);
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Categories', 'कैटेगरी'))),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null, // several tabs have one; no shared hero animation
        onPressed: () => _edit(context, ref, null, async.value),
        icon: const Icon(Icons.add),
        label: Text(context.tr('New category', 'नई कैटेगरी')),
      ),
      body: async.when(
        skipLoadingOnRefresh: true,
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(catalogProvider)),
        data: (catalog) {
          final cats = catalog.categories;
          return ReorderableListView.builder(
            padding: const EdgeInsets.only(bottom: 96),
            itemCount: cats.length,
            onReorderItem: (from, to) => _reorder(context, ref, cats, from, to),
            header: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                context.tr('Drag ≡ to change the order customers see.', 'ग्राहकों के लिए क्रम बदलने के लिए ≡ खींचें।'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            itemBuilder: (_, i) {
              final c = cats[i];
              final count = catalog.products.where((p) => p.categoryId == c.id).length;
              return ListTile(
                key: ValueKey(c.id),
                leading: Text(c.icon ?? '🛍️', style: const TextStyle(fontSize: 30)),
                title: Text(context.pick(c.name, c.nameHi)),
                subtitle: Text(
                  [
                    context.tr('$count products', '$count सामान'),
                    if (!c.isActive) context.tr('hidden', 'छुपी'),
                  ].join(' · '),
                ),
                trailing: const Icon(Icons.drag_handle_rounded),
                onTap: () => _edit(context, ref, c, catalog),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _reorder(BuildContext context, WidgetRef ref, List<Category> cats, int from, int to) async {
    final list = [...cats];
    list.insert(to, list.removeAt(from));
    try {
      for (var i = 0; i < list.length; i++) {
        if (list[i].sortOrder != i + 1) {
          await ref.read(catalogProvider.notifier).saveCategory(list[i].copyWith(sortOrder: i + 1));
        }
      }
    } catch (e) {
      if (context.mounted) showSnack(context, errorText(context, e), error: true);
    }
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, Category? existing, Catalog? catalog) async {
    final result = await showModalBottomSheet<_Result>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CategorySheet(existing: existing, nextOrder: (catalog?.categories.length ?? 0) + 1),
    );
    if (result == null || !context.mounted) return;
    try {
      if (result.delete) {
        await ref.read(catalogProvider.notifier).deleteCategory(existing!.id);
      } else {
        await ref.read(catalogProvider.notifier).saveCategory(result.category!);
      }
      if (context.mounted) showSnack(context, context.tr('Saved ✓', 'सेव हो गया ✓'));
    } catch (e) {
      if (context.mounted) showSnack(context, errorText(context, e), error: true);
    }
  }
}

class _Result {
  const _Result.save(this.category) : delete = false;
  const _Result.delete() : category = null, delete = true;
  final Category? category;
  final bool delete;
}

class _CategorySheet extends StatefulWidget {
  const _CategorySheet({this.existing, required this.nextOrder});
  final Category? existing;
  final int nextOrder;

  @override
  State<_CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends State<_CategorySheet> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _nameHi = TextEditingController(text: widget.existing?.nameHi);
  late String _icon = widget.existing?.icon ?? '🛍️';
  late bool _active = widget.existing?.isActive ?? true;

  @override
  void dispose() {
    _name.dispose();
    _nameHi.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.existing;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.viewInsetsOf(context).bottom + 16),
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                e == null ? context.tr('New category', 'नई कैटेगरी') : context.tr('Edit category', 'कैटेगरी बदलें'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(labelText: context.tr('Name (English) *', 'नाम (English) *')),
                validator: (v) => (v?.trim().isEmpty ?? true) ? context.tr('Required', 'ज़रूरी') : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nameHi,
                decoration: InputDecoration(labelText: context.tr('Name in Hindi', 'हिंदी नाम')),
              ),
              const SizedBox(height: 16),
              Text(context.tr('Icon', 'आइकन')),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final i in _icons)
                    ChoiceChip(
                      label: Text(i, style: const TextStyle(fontSize: 22)),
                      selected: _icon == i,
                      showCheckmark: false,
                      onSelected: (_) => setState(() => _icon = i),
                    ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(context.tr('Show to customers', 'ग्राहकों को दिखाएँ')),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () {
                  if (!_form.currentState!.validate()) return;
                  Navigator.pop(
                    context,
                    _Result.save(
                      Category(
                        id: e?.id ?? const Uuid().v4(),
                        name: _name.text.trim(),
                        nameHi: _nameHi.text.trim().isEmpty ? null : _nameHi.text.trim(),
                        icon: _icon,
                        sortOrder: e?.sortOrder ?? widget.nextOrder,
                        isActive: _active,
                      ),
                    ),
                  );
                },
                child: Text(context.tr('Save', 'सेव करें')),
              ),
              if (e != null) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  icon: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
                  label: Text(
                    context.tr(
                      'Delete category (products stay, without category)',
                      'कैटेगरी हटाएँ (सामान बिना कैटेगरी रहेगा)',
                    ),
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                  onPressed: () => Navigator.pop(context, const _Result.delete()),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
