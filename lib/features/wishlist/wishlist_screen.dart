import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/widgets/product_card.dart';
import '../../theme/app_theme.dart';
import 'wishlist_repository.dart';

/// Displays every product the user has previously wishlisted.
///
/// Pulls from [wishlistListProvider]; shows a friendly empty-state when the
/// list is empty and a retry affordance on network errors.
class WishlistScreen extends ConsumerWidget {
  const WishlistScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(wishlistListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My wishlist')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(wishlistListProvider);
          await ref.read(wishlistIdsProvider.notifier).refresh();
        },
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _ErrorView(
            onRetry: () => ref.invalidate(wishlistListProvider),
          ),
          data: (items) {
            if (items.isEmpty) {
              return _EmptyState(onShop: () => context.go('/'));
            }
            return GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                // Product cards are a touch taller than wide.
                childAspectRatio: 0.62,
              ),
              itemCount: items.length,
              itemBuilder: (context, i) => ProductCard(product: items[i]),
            );
          },
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onShop});
  final VoidCallback onShop;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 80, 24, 24),
      children: [
        const Icon(
          Icons.favorite_border,
          size: 72,
          color: AppColors.textMuted,
        ),
        const SizedBox(height: 14),
        const Text(
          'No wishlisted items yet',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
        ),
        const SizedBox(height: 6),
        const Text(
          'Tap the heart on any product to save it here for later.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textMuted),
        ),
        const SizedBox(height: 18),
        Center(
          child: SizedBox(
            height: 44,
            width: 200,
            child: ElevatedButton.icon(
              onPressed: onShop,
              icon: const Icon(Icons.storefront_outlined),
              label: const Text('Browse products'),
            ),
          ),
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 80, 24, 24),
      children: [
        const Icon(Icons.cloud_off_outlined,
            size: 56, color: AppColors.textMuted),
        const SizedBox(height: 12),
        const Text(
          "Couldn't load your wishlist",
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
        ),
        const SizedBox(height: 14),
        Center(
          child: OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ),
      ],
    );
  }
}
