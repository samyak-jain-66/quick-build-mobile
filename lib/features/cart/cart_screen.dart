import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../shared/models/cart_models.dart';
import '../../shared/widgets/delivery_eta_pill.dart';
import '../../theme/app_theme.dart';
import '../coupons/coupon_sheet.dart';
import 'cart_repository.dart';

final _fmt = NumberFormat.currency(
  locale: 'en_IN',
  symbol: '\u20B9',
  decimalDigits: 0,
);

class CartScreen extends ConsumerWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cartAsync = ref.watch(cartControllerProvider);

    return Scaffold(
      backgroundColor: AppColors.surfaceAlt,
      appBar: AppBar(
        titleSpacing: 16,
        title: cartAsync.maybeWhen(
          data: (s) => _CartAppBarTitle(
            itemCount: s?.totalItems ?? 0,
          ),
          orElse: () => const _CartAppBarTitle(itemCount: 0),
        ),
      ),
      body: cartAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _CartErrorView(
          error: e,
          onShop: () => context.go('/'),
          onRetry: () =>
              ref.read(cartControllerProvider.notifier).refresh(),
        ),
        data: (summary) {
          if (summary == null || summary.groups.isEmpty) {
            return _EmptyState(onShop: () => context.go('/'));
          }
          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                  children: [
                    for (final g in summary.groups) _VendorGroup(group: g),
                    const SizedBox(height: 4),
                    _CouponRow(summary: summary),
                    if (summary.discountTotal > 0) ...[
                      const SizedBox(height: 10),
                      _SavingsBanner(amount: summary.discountTotal),
                    ],
                    const SizedBox(height: 14),
                    _BillDetails(summary: summary),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
              _CheckoutBar(summary: summary),
            ],
          );
        },
      ),
    );
  }
}

class _CartAppBarTitle extends StatelessWidget {
  const _CartAppBarTitle({required this.itemCount});
  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Your cart',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
        ),
        Text(
          itemCount == 0
              ? 'Nothing here yet'
              : '$itemCount ${itemCount == 1 ? 'item' : 'items'}',
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            height: 1.2,
          ),
        ),
      ],
    );
  }
}

class _CartErrorView extends StatelessWidget {
  const _CartErrorView({
    required this.error,
    required this.onShop,
    required this.onRetry,
  });

  final Object error;
  final VoidCallback onShop;
  final VoidCallback onRetry;

  int? get _statusCode {
    final e = error;
    if (e is DioException) {
      return e.response?.statusCode;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final status = _statusCode;

    // A 401/403 simply means the cart is tied to a logged-in session that
    // we can't read right now. Treat it as an empty cart experience rather
    // than exposing raw exception text.
    if (status == 401 || status == 403 || status == 404) {
      return _EmptyState(onShop: onShop);
    }

    final isNetwork = error is DioException &&
        (error as DioException).type != DioExceptionType.badResponse;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(
                Icons.cloud_off_outlined,
                size: 44,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              isNetwork ? 'Can\u2019t reach server' : 'Something went wrong',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            const Text(
              'Please check your connection and try again.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton(
                  onPressed: onShop,
                  child: const Text('Keep shopping'),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _VendorGroup extends StatelessWidget {
  const _VendorGroup({required this.group});
  final CartGroup group;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.outline),
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
            child: Row(
              children: [
                const Icon(Icons.storefront_outlined,
                    size: 18, color: AppColors.textMuted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    group.vendorName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                ),
                DeliveryEtaPill(
                  mode: group.deliveryMode,
                  etaMin: group.etaMinMinutes,
                  etaMax: group.etaMaxMinutes,
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.divider),
          for (int i = 0; i < group.items.length; i++) ...[
            _CartItemRow(item: group.items[i]),
            if (i != group.items.length - 1)
              const Divider(height: 1, color: AppColors.divider, indent: 14),
          ],
        ],
      ),
    );
  }
}

class _CartItemRow extends ConsumerWidget {
  const _CartItemRow({required this.item});
  final CartItem item;

  Future<void> _guard(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Couldn\u2019t update cart, please try again."),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  Future<void> _confirmAndRemove(
    BuildContext context,
    WidgetRef ref,
  ) async {
    // Capture the notifier before any async gap so we never have to touch
    // `ref` on a potentially defunct element after the dialog closes.
    final cart = ref.read(cartControllerProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove item?'),
        content: Text('"${item.name}" will be removed from your cart.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    // Yield a frame so the dialog route finishes unmounting before we
    // mutate cart state. Without this, the synchronous optimistic
    // `state = ...` update races with Riverpod's listener teardown and
    // we hit a `markNeedsBuild on defunct element` assertion.
    await Future<void>.delayed(Duration.zero);

    try {
      await cart.remove(item.id);
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text("Couldn\u2019t update cart, please try again."),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.read(cartControllerProvider.notifier);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.md),
            child: Container(
              width: 72,
              height: 72,
              color: AppColors.surfaceAlt,
              child: item.image != null
                  ? CachedNetworkImage(
                      imageUrl: item.image!,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => const SizedBox.expand(),
                      errorWidget: (_, __, ___) => const Icon(
                        Icons.image_not_supported_outlined,
                        size: 24,
                        color: AppColors.textMuted,
                      ),
                    )
                  : const Icon(
                      Icons.image_not_supported_outlined,
                      size: 24,
                      color: AppColors.textMuted,
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        item.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13.5,
                          height: 1.3,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 32,
                      height: 32,
                      child: IconButton(
                        iconSize: 18,
                        padding: EdgeInsets.zero,
                        splashRadius: 18,
                        tooltip: 'Remove item',
                        onPressed: () => _confirmAndRemove(context, ref),
                        icon: const Icon(
                          Icons.delete_outline,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${_fmt.format(item.unitPrice)} / unit',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _Stepper(
                      quantity: item.quantity,
                      moq: item.moq,
                      onMinus: () => _guard(
                        context,
                        () => cart.update(item.id, item.quantity - 1),
                      ),
                      onPlus: () => _guard(
                        context,
                        () => cart.update(item.id, item.quantity + 1),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _fmt.format(item.lineTotal),
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.quantity,
    required this.moq,
    required this.onMinus,
    required this.onPlus,
  });

  final int quantity;
  final int moq;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    final atMoq = quantity <= moq;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: AppColors.onPrimary, width: 1.2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StepperButton(
            icon: Icons.remove,
            onPressed: atMoq ? null : onMinus,
          ),
          SizedBox(
            width: 30,
            child: Text(
              '$quantity',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 13.5,
              ),
            ),
          ),
          _StepperButton(icon: Icons.add, onPressed: onPlus),
        ],
      ),
    );
  }
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({required this.icon, required this.onPressed});
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    return SizedBox(
      width: 34,
      height: 32,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(AppRadii.pill),
          child: Opacity(
            opacity: disabled ? 0.35 : 1,
            child: Icon(icon, size: 16, color: AppColors.onPrimary),
          ),
        ),
      ),
    );
  }
}

class _CouponRow extends ConsumerWidget {
  const _CouponRow({required this.summary});
  final CartSummary summary;

  Future<void> _openSheet(BuildContext context, WidgetRef ref) async {
    final picked = await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => CouponSheet(
        subtotal: summary.subtotal,
        currentCode: summary.couponCode,
      ),
    );
    if (picked == null) return;
    try {
      await ref
          .read(cartControllerProvider.notifier)
          .setCoupon(picked.isEmpty ? null : picked);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            picked.isEmpty ? 'Coupon removed' : 'Coupon $picked applied',
          ),
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Couldn't update coupon. Please try again."),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final applied = summary.couponCode != null;
    final bg = applied
        ? AppColors.success.withValues(alpha: 0.12)
        : AppColors.primary.withValues(alpha: 0.12);
    final border = applied
        ? AppColors.success.withValues(alpha: 0.45)
        : AppColors.onPrimary.withValues(alpha: 0.55);
    final iconBg =
        applied ? AppColors.success : AppColors.onPrimary;
    final iconData =
        applied ? Icons.check_circle_rounded : Icons.local_offer_rounded;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.md),
        onTap: () => _openSheet(context, ref),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: bg,
            border: Border.all(color: border, width: 1),
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconBg,
                  shape: BoxShape.circle,
                ),
                child: Icon(iconData, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      applied
                          ? '${summary.couponCode} applied'
                          : 'View offers and save more',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      applied
                          ? (summary.discountTotal > 0
                              ? 'You saved ${_fmt.format(summary.discountTotal)}'
                              : 'Tap to change coupon')
                          : 'Tap to see available coupons',
                      style: TextStyle(
                        color: applied
                            ? AppColors.success
                            : AppColors.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              applied
                  ? TextButton(
                      onPressed: () => _openSheet(context, ref),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.text,
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      child: const Text(
                        'Change',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    )
                  : const Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.text,
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SavingsBanner extends StatelessWidget {
  const _SavingsBanner({required this.amount});
  final double amount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(
          color: AppColors.success.withValues(alpha: 0.30),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.celebration_outlined,
            size: 18,
            color: AppColors.success,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: const TextStyle(
                  color: AppColors.success,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                ),
                children: [
                  const TextSpan(text: 'You saved '),
                  TextSpan(
                    text: _fmt.format(amount),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const TextSpan(text: ' on this order'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BillDetails extends StatelessWidget {
  const _BillDetails({required this.summary});
  final CartSummary summary;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Bill details',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5),
          ),
          const SizedBox(height: 8),
          _BillLine(
            label: 'Items total',
            value: _fmt.format(summary.subtotal),
          ),
          if (summary.discountTotal > 0)
            _BillLine(
              label: 'Coupon discount',
              value: '- ${_fmt.format(summary.discountTotal)}',
              highlight: true,
            ),
          _BillLine(
            label: 'Tax',
            value: _fmt.format(summary.taxTotal),
          ),
          _BillLine(
            label: 'Shipping',
            value: summary.shippingTotal == 0
                ? 'FREE'
                : _fmt.format(summary.shippingTotal),
            highlight: summary.shippingTotal == 0,
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1, color: AppColors.divider),
          ),
          Row(
            children: [
              const Text(
                'Total',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
              ),
              const Spacer(),
              Text(
                _fmt.format(summary.grandTotal),
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BillLine extends StatelessWidget {
  const _BillLine({
    required this.label,
    required this.value,
    this.highlight = false,
  });
  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13,
              color: highlight ? AppColors.success : AppColors.text,
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckoutBar extends StatelessWidget {
  const _CheckoutBar({required this.summary});
  final CartSummary summary;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          14, 12, 14, MediaQuery.paddingOf(context).bottom + 12),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 18,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _fmt.format(summary.grandTotal),
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                  height: 1.1,
                ),
              ),
              const Text(
                'to pay',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (summary.discountTotal > 0) ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                  ),
                  child: Text(
                    'Saved ${_fmt.format(summary.discountTotal)}',
                    style: const TextStyle(
                      color: AppColors.success,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const Spacer(),
          SizedBox(
            height: 50,
            child: ElevatedButton.icon(
              onPressed: () => context.push('/checkout'),
              icon: const Icon(Icons.arrow_forward_rounded, size: 18),
              label: const Text('Place order'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 14.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onShop});
  final VoidCallback onShop;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Icon(
              Icons.shopping_cart_outlined,
              size: 44,
              color: AppColors.onPrimary,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Your cart is empty',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          const Text(
            'Add materials or tools to get started',
            style: TextStyle(color: AppColors.textMuted),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
              onPressed: onShop, child: const Text('Start shopping')),
        ],
      ),
    );
  }
}
