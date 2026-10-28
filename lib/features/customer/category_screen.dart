import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_state.dart';
import '../../core/i18n.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/product_widgets.dart';

class CategoryScreen extends ConsumerStatefulWidget {
  const CategoryScreen({super.key, required this.categoryId});
  final String categoryId;

  @override
  ConsumerState<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends ConsumerState<CategoryScreen> {
  late String _selected = widget.categoryId;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(catalogProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          async.value?.category(_selected) == null
              ? ''
              : context.pick(async.value!.category(_selected)!.name, async.value!.category(_selected)!.nameHi),
        ),
        actions: [
          IconButton(
            tooltip: context.tr('Search', 'खोजें'),
            icon: const Icon(Icons.search_rounded),
            onPressed: () => context.push('/shop/search'),
          ),
        ],
      ),
      body: async.when(
        skipLoadingOnRefresh: true,
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(catalogProvider)),
        data: (catalog) {
          final cats = catalog.activeCategories;
          final items = catalog.inCategory(_selected);
          return Column(
            children: [
              SizedBox(
                height: 56,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  itemCount: cats.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => ChoiceChip(
                    label: Text('${cats[i].icon ?? ''} ${context.pick(cats[i].name, cats[i].nameHi)}'),
                    selected: cats[i].id == _selected,
                    onSelected: (_) => setState(() => _selected = cats[i].id),
                  ),
                ),
              ),
              Expanded(
                child: items.isEmpty
                    ? MessageView(
                        icon: Icons.inventory_2_outlined,
                        title: context.tr('Nothing here yet', 'यहाँ अभी कुछ नहीं है'),
                      )
                    : CustomScrollView(
                        slivers: [
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                            sliver: SliverGrid.builder(
                              gridDelegate: productGridDelegate(context),
                              itemCount: items.length,
                              itemBuilder: (_, i) => ProductCard(
                                product: items[i],
                                catalog: catalog,
                                onTap: () => context.push('/shop/p/${items[i].id}'),
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
