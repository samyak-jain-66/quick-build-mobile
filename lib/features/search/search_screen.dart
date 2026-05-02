import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../shared/models/catalog_models.dart';
import '../../shared/widgets/product_card.dart';
import '../../theme/app_theme.dart';
import 'search_repository.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});
  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<SearchSuggestion> _suggestions = const [];
  List<ProductSummary> _results = const [];
  bool _expressOnly = false;
  bool _loading = false;

  @override
  void dispose() {
    _controller.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), () => _fetch(value));
  }

  Future<void> _fetch(String query) async {
    final repo = ref.read(searchRepositoryProvider);
    if (query.trim().length < 2) {
      setState(() {
        _suggestions = const [];
        _results = const [];
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final sug = await repo.suggest(query);
      final res = await repo.run(q: query, expressOnly: _expressOnly);
      if (!mounted) return;
      setState(() {
        _suggestions = sug;
        _results = res.items;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _persistRecent(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    final box = Hive.box<String>('recent_searches');
    final list = box.values
        .where((v) => v.trim().isNotEmpty && v != trimmed)
        .take(9)
        .toList();
    await box.clear();
    await box.put('0', trimmed);
    for (int i = 0; i < list.length; i++) {
      await box.put('${i + 1}', list[i]);
    }
    if (mounted) setState(() {});
  }

  Future<void> _clearRecents() async {
    await Hive.box<String>('recent_searches').clear();
    if (mounted) setState(() {});
  }

  void _runSearch(String term) {
    _controller.text = term;
    _controller.selection =
        TextSelection.collapsed(offset: _controller.text.length);
    _persistRecent(term);
    _fetch(term);
  }

  void _openProduct(SearchSuggestion s) {
    _persistRecent(_controller.text);
    FocusScope.of(context).unfocus();
    context.push('/product/${s.slug}');
  }

  @override
  Widget build(BuildContext context) {
    final recentBox = Hive.box<String>('recent_searches');
    final recents = recentBox.values
        .map((v) => v.trim())
        .where((v) => v.isNotEmpty)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          onChanged: _onChanged,
          onSubmitted: (v) {
            _persistRecent(v);
            _fetch(v);
          },
          decoration: const InputDecoration(
            hintText: 'Search products, brands, categories',
            border: InputBorder.none,
            fillColor: Colors.transparent,
            filled: false,
          ),
        ),
        actions: [
          if (_controller.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                _controller.clear();
                setState(() {
                  _results = const [];
                  _suggestions = const [];
                });
              },
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                FilterChip(
                  selected: _expressOnly,
                  onSelected: (v) {
                    setState(() => _expressOnly = v);
                    _fetch(_controller.text);
                  },
                  label: const Text('Express only'),
                  avatar: const Icon(Icons.bolt, size: 16),
                ),
              ],
            ),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: _results.isEmpty
                ? _SuggestionsList(
                    suggestions: _suggestions,
                    recents: recents,
                    onRecentTap: _runSearch,
                    onSuggestionTap: _openProduct,
                    onClearRecents: recents.isEmpty ? null : _clearRecents,
                  )
                : GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.62,
                    ),
                    itemCount: _results.length,
                    itemBuilder: (context, i) =>
                        ProductCard(product: _results[i]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _SuggestionsList extends StatelessWidget {
  const _SuggestionsList({
    required this.suggestions,
    required this.recents,
    required this.onRecentTap,
    required this.onSuggestionTap,
    required this.onClearRecents,
  });

  final List<SearchSuggestion> suggestions;
  final List<String> recents;
  final void Function(String term) onRecentTap;
  final void Function(SearchSuggestion suggestion) onSuggestionTap;
  final VoidCallback? onClearRecents;

  @override
  Widget build(BuildContext context) {
    final hasRecents = recents.isNotEmpty;
    final hasSuggestions = suggestions.isNotEmpty;
    if (!hasRecents && !hasSuggestions) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Start typing to find products, brands, and categories.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textMuted),
          ),
        ),
      );
    }
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        if (hasRecents) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 6),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Recent searches',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
                if (onClearRecents != null)
                  TextButton(
                    onPressed: onClearRecents,
                    child: const Text('Clear'),
                  ),
              ],
            ),
          ),
          for (final r in recents)
            ListTile(
              leading: const Icon(Icons.history),
              title: Text(r),
              onTap: () => onRecentTap(r),
            ),
          if (hasSuggestions) const Divider(),
        ],
        if (hasSuggestions) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Text(
              'Products',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: AppColors.textMuted,
              ),
            ),
          ),
          for (final s in suggestions)
            ListTile(
              leading: const Icon(Icons.inventory_2_outlined),
              title: Text(
                s.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => onSuggestionTap(s),
            ),
        ],
      ],
    );
  }
}
