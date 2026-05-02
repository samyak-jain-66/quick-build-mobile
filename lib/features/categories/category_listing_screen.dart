import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/catalog_models.dart';
import '../../shared/widgets/product_card.dart';
import '../../theme/app_theme.dart';
import '../product/product_repository.dart';
import 'categories_repository.dart';

class CategoryListingScreen extends ConsumerStatefulWidget {
  const CategoryListingScreen({super.key, required this.slug});
  final String slug;

  @override
  ConsumerState<CategoryListingScreen> createState() =>
      _CategoryListingScreenState();
}

class _CategoryListingScreenState
    extends ConsumerState<CategoryListingScreen> {
  String? _selectedSlug;
  ProductListFilters _filters = const ProductListFilters();

  @override
  Widget build(BuildContext context) {
    final treeAsync = ref.watch(categoriesTreeProvider);

    return Scaffold(
      backgroundColor: AppColors.surfaceAlt,
      body: treeAsync.when(
        loading: () => const _Scaffold(
          title: 'Loading…',
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => _Scaffold(
          title: 'Error',
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Failed to load categories\n$e',
                  textAlign: TextAlign.center),
            ),
          ),
        ),
        data: (tree) => _buildResolved(context, tree),
      ),
    );
  }

  Widget _buildResolved(BuildContext context, List<CategoryNode> tree) {
    final resolved = _resolve(tree, widget.slug);
    if (resolved == null) {
      return _Scaffold(
        title: widget.slug.replaceAll('-', ' ').toUpperCase(),
        child: const Center(child: Text('Category not found')),
      );
    }

    final siblings = resolved.siblings;
    final activeSlug =
        _selectedSlug ?? resolved.selected?.slug ?? siblings.first.slug;
    final selected = siblings.firstWhere(
      (c) => c.slug == activeSlug,
      orElse: () => siblings.first,
    );

    return _Scaffold(
      title: resolved.parentTitle,
      child: Column(
        children: [
          _FilterBar(
            filters: _filters,
            onSort: _pickSort,
            onPrice: _pickPrice,
            onToggleExpress: () => setState(
              () => _filters =
                  _filters.copyWith(expressOnly: !_filters.expressOnly),
            ),
            onClear: () => setState(() => _filters = const ProductListFilters()),
          ),
          Expanded(
            child: Row(
              children: [
                _LeftRail(
                  items: siblings,
                  activeSlug: selected.slug,
                  onTap: (slug) => setState(() {
                    _selectedSlug = slug;
                  }),
                ),
                const VerticalDivider(width: 1, color: AppColors.divider),
                Expanded(
                  child: _ProductsPane(
                    category: selected,
                    filters: _filters,
                    onClearFilters: () =>
                        setState(() => _filters = const ProductListFilters()),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  _ResolvedCategory? _resolve(List<CategoryNode> tree, String slug) {
    for (final parent in tree) {
      if (parent.slug == slug) {
        if (parent.children.isNotEmpty) {
          return _ResolvedCategory(
            parentTitle: parent.name.toUpperCase(),
            siblings: parent.children,
            selected: parent.children.first,
          );
        }
        return _ResolvedCategory(
          parentTitle: parent.name.toUpperCase(),
          siblings: [parent],
          selected: parent,
        );
      }
      for (final child in parent.children) {
        if (child.slug == slug) {
          return _ResolvedCategory(
            parentTitle: parent.name.toUpperCase(),
            siblings: parent.children,
            selected: child,
          );
        }
      }
    }
    return null;
  }

  Future<void> _pickSort() async {
    final result = await showModalBottomSheet<ProductSort>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => _SortSheet(current: _filters.sort),
    );
    if (result != null) {
      setState(() => _filters = _filters.copyWith(sort: result));
    }
  }

  Future<void> _pickPrice() async {
    final result = await showModalBottomSheet<PriceBucket>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => _PriceSheet(current: _filters.priceBucket),
    );
    if (result != null) {
      setState(() => _filters = _filters.copyWith(priceBucket: result));
    }
  }
}

class _ResolvedCategory {
  _ResolvedCategory({
    required this.parentTitle,
    required this.siblings,
    required this.selected,
  });
  final String parentTitle;
  final List<CategoryNode> siblings;
  final CategoryNode? selected;
}

class _Scaffold extends StatelessWidget {
  const _Scaffold({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Container(
            color: AppColors.surface,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1, color: AppColors.divider),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.filters,
    required this.onSort,
    required this.onPrice,
    required this.onToggleExpress,
    required this.onClear,
  });

  final ProductListFilters filters;
  final VoidCallback onSort;
  final VoidCallback onPrice;
  final VoidCallback onToggleExpress;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _FilterChip(
                    label: _sortLabel(filters.sort),
                    icon: Icons.swap_vert_rounded,
                    active: filters.sort != ProductSort.relevance,
                    onTap: onSort,
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: _priceLabel(filters.priceBucket),
                    icon: Icons.currency_rupee_rounded,
                    active: filters.priceBucket != PriceBucket.any,
                    onTap: onPrice,
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'Express',
                    icon: Icons.bolt_rounded,
                    active: filters.expressOnly,
                    onTap: onToggleExpress,
                  ),
                ],
              ),
            ),
          ),
          if (filters.isActive) ...[
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: onClear,
              icon: const Icon(Icons.close_rounded, size: 16),
              label: const Text('Clear'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.danger,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _sortLabel(ProductSort s) {
    switch (s) {
      case ProductSort.priceAsc:
        return 'Price: low to high';
      case ProductSort.priceDesc:
        return 'Price: high to low';
      case ProductSort.newest:
        return 'Newest';
      case ProductSort.relevance:
        return 'Sort';
    }
  }

  String _priceLabel(PriceBucket b) {
    switch (b) {
      case PriceBucket.under100:
        return 'Under ₹100';
      case PriceBucket.between100And500:
        return '₹100 – ₹500';
      case PriceBucket.between500And2k:
        return '₹500 – ₹2k';
      case PriceBucket.above2k:
        return '₹2k +';
      case PriceBucket.any:
        return 'Price';
    }
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? AppColors.onPrimary : AppColors.surface,
      shape: StadiumBorder(
        side: BorderSide(
          color: active ? AppColors.onPrimary : AppColors.outline,
        ),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: active ? AppColors.primary : AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                  color: active ? Colors.white : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LeftRail extends StatelessWidget {
  const _LeftRail({
    required this.items,
    required this.activeSlug,
    required this.onTap,
  });
  final List<CategoryNode> items;
  final String activeSlug;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      color: AppColors.surfaceAlt,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: items.length,
        itemBuilder: (context, i) {
          final c = items[i];
          final isActive = c.slug == activeSlug;
          return InkWell(
            onTap: () => onTap(c.slug),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
              decoration: BoxDecoration(
                color: isActive ? AppColors.surface : Colors.transparent,
                border: Border(
                  left: BorderSide(
                    color: isActive ? AppColors.primary : Colors.transparent,
                    width: 4,
                  ),
                ),
              ),
              child: Column(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: isActive
                          ? AppColors.primary
                          : AppColors.surfaceMuted,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.construction,
                      color: isActive
                          ? AppColors.onPrimary
                          : AppColors.textSecondary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      c.name,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight:
                            isActive ? FontWeight.w800 : FontWeight.w600,
                        color: isActive
                            ? AppColors.text
                            : AppColors.textSecondary,
                        height: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ProductsPane extends ConsumerWidget {
  const _ProductsPane({
    required this.category,
    required this.filters,
    required this.onClearFilters,
  });
  final CategoryNode category;
  final ProductListFilters filters;
  final VoidCallback onClearFilters;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncProducts = ref.watch(
      filteredCategoryProductsProvider(
        FilteredProductsKey(category.slug, filters),
      ),
    );

    return Container(
      color: AppColors.surface,
      child: asyncProducts.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorView(
          message: 'Could not load products',
          onRetry: () => ref.invalidate(
            filteredCategoryProductsProvider(
              FilteredProductsKey(category.slug, filters),
            ),
          ),
        ),
        data: (items) {
          if (items.isEmpty) {
            return _EmptyView(
              hasFilters: filters.isActive,
              category: category.name,
              onClearFilters: onClearFilters,
            );
          }
          return _ProductGrid(items: items, categoryName: category.name);
        },
      ),
    );
  }
}

class _ProductGrid extends StatelessWidget {
  const _ProductGrid({required this.items, required this.categoryName});
  final List<ProductSummary> items;
  final String categoryName;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          sliver: SliverToBoxAdapter(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    categoryName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  '${items.length} items',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.56,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) => ProductCard(product: items[i]),
              childCount: items.length,
            ),
          ),
        ),
      ],
    );
  }
}

class _SortSheet extends StatelessWidget {
  const _SortSheet({required this.current});
  final ProductSort current;

  @override
  Widget build(BuildContext context) {
    final options = <MapEntry<ProductSort, String>>[
      const MapEntry(ProductSort.relevance, 'Relevance'),
      const MapEntry(ProductSort.priceAsc, 'Price: low to high'),
      const MapEntry(ProductSort.priceDesc, 'Price: high to low'),
      const MapEntry(ProductSort.newest, 'Newest first'),
    ];
    return _OptionsSheet<ProductSort>(
      title: 'Sort by',
      current: current,
      options: options,
    );
  }
}

class _PriceSheet extends StatelessWidget {
  const _PriceSheet({required this.current});
  final PriceBucket current;

  @override
  Widget build(BuildContext context) {
    final options = <MapEntry<PriceBucket, String>>[
      const MapEntry(PriceBucket.any, 'Any price'),
      const MapEntry(PriceBucket.under100, 'Under ₹100'),
      const MapEntry(PriceBucket.between100And500, '₹100 – ₹500'),
      const MapEntry(PriceBucket.between500And2k, '₹500 – ₹2,000'),
      const MapEntry(PriceBucket.above2k, '₹2,000 and above'),
    ];
    return _OptionsSheet<PriceBucket>(
      title: 'Price',
      current: current,
      options: options,
    );
  }
}

class _OptionsSheet<T> extends StatelessWidget {
  const _OptionsSheet({
    required this.title,
    required this.current,
    required this.options,
  });
  final String title;
  final T current;
  final List<MapEntry<T, String>> options;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Text(title,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800)),
          ),
          for (final e in options)
            InkWell(
              onTap: () => Navigator.of(context).pop(e.key),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 12),
                child: Row(
                  children: [
                    Icon(
                      e.key == current
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_unchecked_rounded,
                      color: e.key == current
                          ? AppColors.onPrimary
                          : AppColors.textMuted,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      e.value,
                      style: TextStyle(
                        fontWeight: e.key == current
                            ? FontWeight.w800
                            : FontWeight.w600,
                        fontSize: 14.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView({
    required this.hasFilters,
    required this.category,
    required this.onClearFilters,
  });
  final bool hasFilters;
  final String category;
  final VoidCallback onClearFilters;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(32),
              ),
              child: const Icon(Icons.inventory_2_outlined,
                  size: 28, color: AppColors.textMuted),
            ),
            const SizedBox(height: 14),
            Text(
              hasFilters ? 'No products match these filters' : 'No products yet',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              hasFilters
                  ? 'Try clearing a filter to see more $category items.'
                  : 'Check back soon for new $category items.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (hasFilters) ...[
              const SizedBox(height: 14),
              OutlinedButton(
                onPressed: onClearFilters,
                child: const Text('Clear filters'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded,
                size: 36, color: AppColors.textMuted),
            const SizedBox(height: 10),
            Text(message,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
