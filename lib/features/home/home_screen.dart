import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/widgets/product_card.dart';
import '../../shared/widgets/section_header.dart';
import '../../theme/app_theme.dart';
import '../categories/categories_repository.dart';
import '../location/location_controller.dart';
import '../location/location_models.dart';
import '../location/location_sheet.dart';
import '../location/not_serviceable_view.dart';
import '../product/product_repository.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _autoOpened = false;

  void _maybeAutoOpen(ServiceableLocation? location) {
    // Only auto-open the picker once per session when the user has never
    // saved a location before.
    if (_autoOpened || location != null) return;
    _autoOpened = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => const LocationSheet(),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final locationAsync = ref.watch(locationProvider);
    final location = locationAsync.valueOrNull;
    _maybeAutoOpen(location);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _HomeHeader(location: location),
            Expanded(child: _buildBody(location)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(ServiceableLocation? location) {
    if (location == null) {
      return const _LocationPrompt();
    }
    if (!location.isServiceable) {
      return NotServiceableView(location: location);
    }
    return const _ServiceableHome();
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.location});
  final ServiceableLocation? location;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _LocationChip(location: location),
              ),
              const SizedBox(width: 8),
              CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.surfaceAlt,
                child: IconButton(
                  iconSize: 18,
                  icon: const Icon(Icons.notifications_none),
                  onPressed: () {},
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: () => context.go('/search'),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
              child: Row(
                children: const [
                  Icon(Icons.search, color: AppColors.textMuted),
                  SizedBox(width: 8),
                  Text(
                    'Search cement, TMT, tiles, paint...',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LocationChip extends StatelessWidget {
  const _LocationChip({required this.location});
  final ServiceableLocation? location;

  String get _caption {
    if (location == null) return 'Set your delivery location';
    if (!location!.isServiceable) return 'Not serviceable yet';
    return 'Deliver in 10 min to';
  }

  String get _placeLine {
    if (location == null) return 'Tap to add a pincode';
    final city = location!.city;
    if (city != null && city.isNotEmpty) {
      return '$city \u2022 ${location!.pincode}';
    }
    return 'Pincode ${location!.pincode}';
  }

  Future<void> _open(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const LocationSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasLocation = location != null;
    final serviceable = location?.isServiceable ?? false;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.md),
        onTap: () => _open(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: 4, vertical: 4),
          child: Row(
            children: [
              Icon(
                hasLocation && !serviceable
                    ? Icons.explore_off_rounded
                    : Icons.location_on_rounded,
                size: 18,
                color: hasLocation && !serviceable
                    ? AppColors.warning
                    : null,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _caption,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      _placeLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: AppColors.textMuted,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LocationPrompt extends StatelessWidget {
  const _LocationPrompt();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.location_on_rounded,
                size: 34,
                color: AppColors.onPrimary,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Where should we deliver?',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            const Text(
              'Add your pincode to see products and offers available in your area.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 46,
              child: ElevatedButton.icon(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  showDragHandle: true,
                  builder: (_) => const LocationSheet(),
                ),
                icon: const Icon(Icons.edit_location_alt_outlined, size: 18),
                label: const Text('Set delivery location'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServiceableHome extends ConsumerWidget {
  const _ServiceableHome();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(categoriesTreeProvider);
    final featuredAsync = ref.watch(featuredProductsProvider);

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _ExpressBanner()),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
            child: SectionHeader(
              title: 'Shop by category',
              trailing: TextButton(
                onPressed: () => context.go('/categories'),
                child: const Text('See all'),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 250,
            child: categoriesAsync.when(
              loading: () => const Center(
                  child: CircularProgressIndicator(strokeWidth: 2)),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (cats) {
                final topLevel = cats.take(8).toList();
                return GridView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  scrollDirection: Axis.horizontal,
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 0.9,
                  ),
                  itemCount: topLevel.length,
                  itemBuilder: (context, i) {
                    final c = topLevel[i];
                    return InkWell(
                      onTap: () => context.push('/categories/${c.slug}'),
                      borderRadius: BorderRadius.circular(AppRadii.md),
                      child: Container(
                        width: 110,
                        decoration: BoxDecoration(
                          color: AppColors.surfaceAlt,
                          borderRadius: BorderRadius.circular(AppRadii.md),
                        ),
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.construction,
                                color: AppColors.onPrimary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              c.name,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 10),
            child: SectionHeader(
              title: 'Top picks for your site',
              subtitle: 'Hand-picked by our construction experts',
            ),
          ),
        ),
        featuredAsync.when(
          loading: () => const SliverToBoxAdapter(
            child: SizedBox(
              height: 240,
              child: Center(
                  child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          ),
          error: (e, _) => SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Error: $e',
                  style: const TextStyle(color: AppColors.danger)),
            ),
          ),
          data: (items) => SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.62,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) => ProductCard(product: items[i]),
                childCount: items.length,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ExpressBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.onPrimary,
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(AppRadii.sm),
            ),
            child: const Icon(Icons.bolt, color: AppColors.onPrimary, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: const [
                Text(
                  'Express delivery in 10 minutes',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14.5,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'On select bricks, cement, paints and tools nearby',
                  style: TextStyle(
                    color: Color(0xFFBFBFBF),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
