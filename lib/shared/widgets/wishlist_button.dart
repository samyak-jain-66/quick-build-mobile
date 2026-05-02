import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/wishlist/wishlist_repository.dart';
import '../../theme/app_theme.dart';

/// A heart-shaped toggle that reflects the current wishlist state for a
/// given product and optimistically updates it when tapped.
///
/// Looks good in an [AppBar] action slot or overlaid on a product image; the
/// colours are chosen for both.
class WishlistButton extends ConsumerWidget {
  const WishlistButton({
    super.key,
    required this.productId,
    this.productName,
    this.size = 22,
    this.padded = true,
    this.onColor,
  });

  final String productId;
  final String? productName;
  final double size;
  final bool padded;

  /// When provided, the icon is tinted with this colour in the "not
  /// wishlisted" state (useful when rendered over a dark image).
  final Color? onColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final idsAsync = ref.watch(wishlistIdsProvider);
    final isWishlisted = idsAsync.maybeWhen(
      data: (ids) => ids.contains(productId),
      orElse: () => false,
    );

    final icon = Icon(
      isWishlisted ? Icons.favorite : Icons.favorite_border,
      color: isWishlisted
          ? Colors.redAccent
          : (onColor ?? AppColors.text),
      size: size,
    );

    return IconButton(
      icon: icon,
      padding: padded ? null : EdgeInsets.zero,
      constraints: padded ? null : const BoxConstraints(),
      tooltip: isWishlisted ? 'Remove from wishlist' : 'Add to wishlist',
      onPressed: () async {
        final messenger = ScaffoldMessenger.of(context);
        try {
          final nowAdded =
              await ref.read(wishlistIdsProvider.notifier).toggle(productId);
          messenger.showSnackBar(
            SnackBar(
              duration: const Duration(seconds: 2),
              content: Text(
                nowAdded
                    ? '${productName ?? 'Item'} added to wishlist'
                    : '${productName ?? 'Item'} removed from wishlist',
              ),
            ),
          );
        } catch (e) {
          messenger.showSnackBar(
            SnackBar(
              content: Text("Couldn't update wishlist. Sign in and try again."),
              backgroundColor: Colors.red.shade600,
            ),
          );
        }
      },
    );
  }
}
