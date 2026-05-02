import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../theme/app_theme.dart';
import '../models/catalog_models.dart';
import 'delivery_eta_pill.dart';
import 'price_tag.dart';
import 'wishlist_button.dart';

class ProductCard extends StatelessWidget {
  const ProductCard({super.key, required this.product});
  final ProductSummary product;

  @override
  Widget build(BuildContext context) {
    final hasBrand = (product.brandName ?? '').trim().isNotEmpty;
    final hasMoq = product.moq > 1;

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: InkWell(
        onTap: () => context.push('/product/${product.slug}'),
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.outline),
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.max,
            children: [
              AspectRatio(
                aspectRatio: 1.4,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (product.images.isNotEmpty)
                        CachedNetworkImage(
                          imageUrl: product.images.first,
                          fit: BoxFit.cover,
                          placeholder: (_, __) =>
                              Container(color: AppColors.surfaceAlt),
                          errorWidget: (_, __, ___) => Container(
                            color: AppColors.surfaceAlt,
                            alignment: Alignment.center,
                            child: const Icon(
                              Icons.broken_image_outlined,
                              size: 28,
                              color: AppColors.textMuted,
                            ),
                          ),
                        )
                      else
                        Container(
                          color: AppColors.surfaceAlt,
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.image_outlined,
                            size: 28,
                            color: AppColors.textMuted,
                          ),
                        ),
                      if (product.discountPct > 0)
                        Positioned(
                          top: 6,
                          left: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${product.discountPct.toStringAsFixed(0)}% OFF',
                              style: const TextStyle(
                                color: AppColors.onPrimary,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                      Positioned(
                        top: 2,
                        right: 2,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.85),
                            shape: BoxShape.circle,
                          ),
                          child: WishlistButton(
                            productId: product.id,
                            productName: product.name,
                            size: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 22,
                child: product.expressEligible
                    ? const Align(
                        alignment: Alignment.centerLeft,
                        child: DeliveryEtaPill(
                          mode: 'express',
                          etaMin: 10,
                          etaMax: 30,
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Flexible(
                      child: Text(
                        product.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                          height: 1.25,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hasBrand ? product.brandName! : '\u00A0',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              PriceTag(
                price: product.displayPrice,
                basePrice: product.discountPct > 0 ? product.basePrice : null,
                discountPct:
                    product.discountPct > 0 ? product.discountPct : null,
                compact: true,
              ),
              const SizedBox(height: 4),
              SizedBox(
                height: 14,
                child: Text(
                  hasMoq ? 'MOQ ${product.moq}' : '',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
