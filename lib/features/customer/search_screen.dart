import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_state.dart';
import '../../core/i18n.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/product_widgets.dart';
import '../../domain/search.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});
  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  String _query = '';

  static const _suggestions = ['atta', 'cheeni', 'aloo', 'tel', 'doodh', 'dal', 'chai', 'sabun'];

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 180), () => setState(() => _query = v));
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(catalogProvider).value;
    final results = catalog == null ? const [] : searchProducts(_query, catalog.visibleProducts, catalog: catalog);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: _onChanged,
          decoration: InputDecoration(
            hintText: context.tr('Search in English or Hindi', 'हिंदी या English में खोजें'),
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    tooltip: context.tr('Clear', 'साफ़ करें'),
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _controller.clear();
                      setState(() => _query = '');
                    },
                  ),
          ),
        ),
      ),
      body: catalog == null
          ? const LoadingView()
          : _query.trim().isEmpty
          ? ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(context.tr('Popular searches', 'लोकप्रिय खोज'), style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final s in _suggestions)
                      ActionChip(
                        label: Text(s),
                        onPressed: () {
                          _controller.text = s;
                          setState(() => _query = s);
                        },
                      ),
                  ],
                ),
              ],
            )
          : results.isEmpty
          ? MessageView(
              icon: Icons.search_off_rounded,
              title: context.tr('No match for "$_query"', '"$_query" नहीं मिला'),
              message: context.tr(
                'Try another word, e.g. "chawal" or "rice".',
                'दूसरा शब्द आज़माएँ, जैसे "चावल" या "rice"।',
              ),
            )
          : CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverGrid.builder(
                    gridDelegate: productGridDelegate(context),
                    itemCount: results.length,
                    itemBuilder: (_, i) => ProductCard(
                      product: results[i],
                      catalog: catalog,
                      onTap: () => context.push('/shop/p/${results[i].id}'),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
