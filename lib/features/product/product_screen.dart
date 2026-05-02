import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../shared/models/catalog_models.dart';
import '../../shared/widgets/delivery_eta_pill.dart';
import '../../shared/widgets/price_tag.dart';
import '../../shared/widgets/product_card.dart';
import '../../shared/widgets/section_header.dart';
import '../../shared/widgets/wishlist_button.dart';
import '../../theme/app_theme.dart';
import '../cart/cart_repository.dart';
import '../checkout/buy_now_session.dart';
import 'product_repository.dart';
import 'product_share.dart';

final _fmt = NumberFormat.currency(
  locale: 'en_IN',
  symbol: '\u20B9',
  decimalDigits: 0,
);

class ProductScreen extends ConsumerStatefulWidget {
  const ProductScreen({super.key, required this.slug});
  final String slug;
  @override
  ConsumerState<ProductScreen> createState() => _ProductScreenState();
}

class _ProductScreenState extends ConsumerState<ProductScreen> {
  int _quantity = 1;
  int _imageIndex = 0;

  @override
  Widget build(BuildContext context) {
    final productAsync = ref.watch(productDetailProvider(widget.slug));
    final similar = ref.watch(similarProductsProvider(widget.slug));
    final fbt = ref.watch(fbtProductsProvider(widget.slug));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Product'),
        actions: [
          productAsync.maybeWhen(
            data: (p) => WishlistButton(
              productId: p.id,
              productName: p.name,
            ),
            orElse: () => const SizedBox.shrink(),
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Share via WhatsApp',
            onPressed: () => _onShare(productAsync.value),
          ),
        ],
      ),
      body: productAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (p) {
          _quantity = _quantity < p.moq ? p.moq : _quantity;
          final unitPrice = _tierPrice(p, _quantity);
          return Stack(
            fit: StackFit.expand,
            children: [
              ListView(
                padding: const EdgeInsets.only(bottom: 140),
                children: [
                  _ImageGallery(
                    images: p.images,
                    index: _imageIndex,
                    onChange: (i) => setState(() => _imageIndex = i),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (p.brandName != null)
                          Text(
                            p.brandName!.toUpperCase(),
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1,
                              fontSize: 11,
                            ),
                          ),
                        const SizedBox(height: 4),
                        Text(
                          p.name,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            if (p.expressEligible)
                              DeliveryEtaPill(
                                  mode: 'express', etaMin: 10, etaMax: 30),
                            const SizedBox(width: 8),
                            if (p.vendorName != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceAlt,
                                  borderRadius:
                                      BorderRadius.circular(AppRadii.pill),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.star,
                                        size: 14, color: Colors.amber),
                                    const SizedBox(width: 3),
                                    Text(
                                      p.vendorRating.toStringAsFixed(1),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      p.vendorName!,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        PriceTag(
                          price: unitPrice,
                          basePrice:
                              p.discountPct > 0 ? p.basePrice : null,
                          discountPct:
                              p.discountPct > 0 ? p.discountPct : null,
                        ),
                        if (p.moq > 1) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Minimum order quantity: ${p.moq} ${p.unit}',
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontWeight: FontWeight.w600,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                        if (p.tiers.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          const Text(
                            'Bulk pricing',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14.5,
                            ),
                          ),
                          const SizedBox(height: 6),
                          _BulkTierTable(tiers: p.tiers, unit: p.unit),
                        ],
                        const SizedBox(height: 20),
                        _QuantityStepper(
                          moq: p.moq,
                          value: _quantity,
                          unit: p.unit,
                          onChange: (v) => setState(() => _quantity = v),
                        ),
                        const SizedBox(height: 20),
                        if (p.description != null) ...[
                          const SectionHeader(title: 'About this product'),
                          const SizedBox(height: 6),
                          Text(
                            p.description!,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              height: 1.45,
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        if (p.specs.isNotEmpty) ...[
                          const SectionHeader(title: 'Specifications'),
                          const SizedBox(height: 10),
                          _SpecTable(specs: p.specs),
                          const SizedBox(height: 20),
                        ],
                        _ReviewsBlock(productId: p.id),
                        const SizedBox(height: 24),
                        if (fbt.hasValue && fbt.value!.isNotEmpty) ...[
                          const SectionHeader(
                            title: 'Frequently bought together',
                          ),
                          const SizedBox(height: 10),
                          _HorizontalRail(items: fbt.value!),
                          const SizedBox(height: 20),
                        ],
                        if (similar.hasValue && similar.value!.isNotEmpty) ...[
                          const SectionHeader(title: 'Similar products'),
                          const SizedBox(height: 10),
                          _HorizontalRail(items: similar.value!),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _BottomBar(
                  totalPrice: unitPrice * _quantity,
                  onAdd: () async {
                    await ref
                        .read(cartControllerProvider.notifier)
                        .add(productId: p.id, quantity: _quantity);
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('${p.name} added to cart'),
                      ),
                    );
                  },
                  onBuyNow: () {
                    ref.read(buyNowSessionProvider.notifier).state =
                        BuyNowSession(
                      productId: p.id,
                      productName: p.name,
                      image: p.images.isNotEmpty ? p.images.first : null,
                      vendorId: p.vendorId,
                      vendorName: p.vendorName ?? 'Vendor',
                      quantity: _quantity,
                      unitPrice: unitPrice,
                      taxPct: p.taxPct,
                      deliveryMode:
                          p.expressEligible ? 'express' : 'standard',
                      etaMinMinutes: p.expressEligible ? 10 : 1440,
                      etaMaxMinutes: p.expressEligible ? 30 : 2880,
                    );
                    context.push('/checkout');
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  double _tierPrice(ProductDetail p, int qty) {
    double? tier;
    for (final t in p.tiers) {
      if (qty >= t.minQty) tier = t.price;
    }
    return tier ?? p.displayPrice;
  }

  Future<void> _onShare(ProductDetail? p) async {
    if (p == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final outcome = await ProductShare.shareToWhatsApp(
        name: p.name,
        slug: p.slug,
        price: p.displayPrice,
        brand: p.brandName,
      );
      if (!mounted) return;
      if (outcome == ShareOutcome.copiedToClipboard) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'WhatsApp not available. Product link copied to clipboard.',
            ),
          ),
        );
      }
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't open WhatsApp")),
      );
    }
  }
}

class _ImageGallery extends StatelessWidget {
  const _ImageGallery({
    required this.images,
    required this.index,
    required this.onChange,
  });

  final List<String> images;
  final int index;
  final ValueChanged<int> onChange;

  @override
  Widget build(BuildContext context) {
    if (images.isEmpty) {
      return Container(
        color: AppColors.surfaceAlt,
        height: 320,
        alignment: Alignment.center,
        child: const Icon(
          Icons.image_not_supported_outlined,
          size: 48,
          color: AppColors.textMuted,
        ),
      );
    }
    return Column(
      children: [
        Container(
          color: AppColors.surfaceAlt,
          height: 320,
          child: PageView.builder(
            itemCount: images.length,
            onPageChanged: onChange,
            itemBuilder: (context, i) => CachedNetworkImage(
              imageUrl: images[i],
              fit: BoxFit.cover,
              width: double.infinity,
              placeholder: (_, __) => Container(
                color: AppColors.surfaceAlt,
                alignment: Alignment.center,
                child: const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
              errorWidget: (_, __, ___) => Container(
                color: AppColors.surfaceAlt,
                alignment: Alignment.center,
                child: const Icon(
                  Icons.broken_image_outlined,
                  size: 48,
                  color: AppColors.textMuted,
                ),
              ),
            ),
          ),
        ),
        if (images.length > 1) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              images.length,
              (i) => AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: i == index ? 18 : 6,
                height: 6,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: i == index ? AppColors.primary : AppColors.outline,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _BulkTierTable extends StatelessWidget {
  const _BulkTierTable({required this.tiers, required this.unit});
  final List<BulkPricingTier> tiers;
  final String unit;
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          for (int i = 0; i < tiers.length; i++) ...[
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Text(
                    '${tiers[i].minQty}+ $unit',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    _fmt.format(tiers[i].price),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'BEST',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: AppColors.onPrimary,
                    ),
                  ),
                ),
              ],
            ),
            if (i != tiers.length - 1)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Divider(height: 1),
              ),
          ],
        ],
      ),
    );
  }
}

class _QuantityStepper extends StatelessWidget {
  const _QuantityStepper({
    required this.moq,
    required this.value,
    required this.unit,
    required this.onChange,
  });
  final int moq;
  final int value;
  final String unit;
  final ValueChanged<int> onChange;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Text('Quantity',
            style:
                TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
        const Spacer(),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(AppRadii.pill),
          ),
          child: Row(
            children: [
              IconButton(
                onPressed: value > moq ? () => onChange(value - 1) : null,
                icon: const Icon(Icons.remove),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  '$value $unit',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => onChange(value + 1),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SpecTable extends StatelessWidget {
  const _SpecTable({required this.specs});
  final Map<String, dynamic> specs;
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.outline),
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Column(
        children: [
          for (int i = 0; i < specs.length; i++) ...[
            _SpecRow(
              label: specs.keys.elementAt(i),
              value: specs.values.elementAt(i),
              alt: i.isOdd,
            ),
          ],
        ],
      ),
    );
  }
}

class _SpecRow extends StatelessWidget {
  const _SpecRow({required this.label, required this.value, required this.alt});
  final String label;
  final dynamic value;
  final bool alt;
  @override
  Widget build(BuildContext context) {
    return Container(
      color: alt ? AppColors.surfaceAlt : AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Text(
              label
                  .replaceAll('_', ' ')
                  .replaceFirstMapped(RegExp(r'\b[a-z]'),
                      (m) => m.group(0)!.toUpperCase()),
              style: const TextStyle(
                color: AppColors.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            flex: 5,
            child: Text(
              value is List ? value.join(', ') : value?.toString() ?? '',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewsBlock extends ConsumerWidget {
  const _ReviewsBlock({required this.productId});
  final String productId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviews = ref.watch(productReviewsProvider(productId));
    return reviews.when(
      loading: () => const SizedBox(
        height: 60,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (e, _) => const SizedBox.shrink(),
      data: (data) {
        final total = data['total'] as int? ?? 0;
        final avg = (data['average'] as num?)?.toDouble() ?? 0;
        final items = (data['items'] as List?) ?? const [];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              title: 'Ratings & reviews',
              subtitle: total == 0 ? null : '$total reviews',
              trailing: Row(
                children: [
                  const Icon(Icons.star, color: Colors.amber, size: 18),
                  const SizedBox(width: 4),
                  Text(
                    avg.toStringAsFixed(1),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            if (items.isEmpty)
              const Text(
                'No reviews yet. Be the first to review after delivery.',
                style: TextStyle(color: AppColors.textMuted),
              )
            else
              for (final r in items.take(3))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: _ReviewTile(review: Map<String, dynamic>.from(r)),
                ),
          ],
        );
      },
    );
  }
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({required this.review});
  final Map<String, dynamic> review;
  @override
  Widget build(BuildContext context) {
    final profile = review['profiles'] as Map?;
    final rating = (review['rating'] as num?)?.toInt() ?? 0;
    final title = review['title'] as String?;
    final body = review['body'] as String?;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadii.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                profile?['full_name']?.toString() ?? 'Customer',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              Row(
                children: List.generate(
                  5,
                  (i) => Icon(
                    i < rating ? Icons.star : Icons.star_outline,
                    color: Colors.amber,
                    size: 14,
                  ),
                ),
              ),
            ],
          ),
          if (title != null && title.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
          if (body != null && body.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(body,
                style: const TextStyle(color: AppColors.textSecondary)),
          ],
        ],
      ),
    );
  }
}

class _HorizontalRail extends StatelessWidget {
  const _HorizontalRail({required this.items});
  final List<ProductSummary> items;
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 280,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) => SizedBox(
          width: 170,
          child: ProductCard(product: items[i]),
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.totalPrice,
    required this.onAdd,
    required this.onBuyNow,
  });
  final double totalPrice;
  final VoidCallback onAdd;
  final VoidCallback onBuyNow;
  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Total',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        _fmt.format(totalPrice),
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 20,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 46,
                      child: OutlinedButton.icon(
                        onPressed: onBuyNow,
                        icon: const Icon(Icons.flash_on_rounded, size: 18),
                        label: const Text('Buy now'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.text,
                          side: const BorderSide(
                            color: AppColors.onPrimary,
                            width: 1.4,
                          ),
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 46,
                      child: ElevatedButton.icon(
                        onPressed: onAdd,
                        icon:
                            const Icon(Icons.add_shopping_cart, size: 18),
                        label: const Text('Add to cart'),
                        style: ElevatedButton.styleFrom(
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
