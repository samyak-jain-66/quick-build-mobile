import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../theme/app_theme.dart';
import 'coupons_repository.dart';

/// Bottom sheet that lists featured coupons and lets the user apply or
/// remove one. The sheet closes with:
/// - a code string  -> caller should apply that code
/// - an empty string -> caller should clear the current coupon
/// - null            -> dismissed, no change
class CouponSheet extends ConsumerStatefulWidget {
  const CouponSheet({
    super.key,
    required this.subtotal,
    this.currentCode,
  });

  final double subtotal;
  final String? currentCode;

  @override
  ConsumerState<CouponSheet> createState() => _CouponSheetState();
}

class _CouponSheetState extends ConsumerState<CouponSheet> {
  String? _busyCode;

  Future<void> _apply(String code) async {
    if (_busyCode != null) return;
    setState(() => _busyCode = code);
    try {
      await ref.read(couponsRepositoryProvider).validate(
            code: code,
            subtotal: widget.subtotal,
          );
      if (!mounted) return;
      Navigator.of(context).pop(code);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busyCode = null);
      final msg = _errorMessage(e);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  String _errorMessage(Object e) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map && data['message'] is String) {
        return data['message'] as String;
      }
      if (e.response?.statusCode == 400) return 'Coupon not applicable';
    }
    return "Couldn't apply coupon. Please try again.";
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(featuredCouponsProvider);
    final currentCode = widget.currentCode;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 4, 20, 4),
                child: Row(
                  children: [
                    Icon(Icons.local_offer_outlined, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Available offers',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: AppColors.divider),
              Flexible(
                child: async.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (e, _) => Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      "Couldn't load offers. $e",
                      style: const TextStyle(color: AppColors.textMuted),
                    ),
                  ),
                  data: (coupons) {
                    if (coupons.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(
                          child: Text(
                            'No offers available right now.',
                            style: TextStyle(color: AppColors.textMuted),
                          ),
                        ),
                      );
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      shrinkWrap: true,
                      itemCount: coupons.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        final c = coupons[i];
                        final selected = currentCode == c.code;
                        final busy = _busyCode == c.code;
                        return _CouponCard(
                          coupon: c,
                          selected: selected,
                          busy: busy,
                          onApply: () => _apply(c.code),
                        );
                      },
                    );
                  },
                ),
              ),
              if (currentCode != null && currentCode.isNotEmpty) ...[
                const Divider(height: 1, color: AppColors.divider),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _busyCode != null
                          ? null
                          : () => Navigator.of(context).pop(''),
                      icon: const Icon(Icons.remove_circle_outline, size: 18),
                      label: Text('Remove coupon $currentCode'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.danger,
                        side: const BorderSide(color: AppColors.danger),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CouponCard extends StatelessWidget {
  const _CouponCard({
    required this.coupon,
    required this.selected,
    required this.busy,
    required this.onApply,
  });

  final CouponSummary coupon;
  final bool selected;
  final bool busy;
  final VoidCallback onApply;

  static final _money = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '\u20B9',
    decimalDigits: 0,
  );

  String get _headline {
    if (coupon.type == 'flat') {
      return '${_money.format(coupon.value)} off';
    }
    return '${coupon.value.toStringAsFixed(0)}% off';
  }

  String? get _subline {
    final bits = <String>[];
    if (coupon.minOrderAmount > 0) {
      bits.add('Min ${_money.format(coupon.minOrderAmount)}');
    }
    if (coupon.maxDiscount != null && coupon.maxDiscount! > 0) {
      bits.add('Max ${_money.format(coupon.maxDiscount)} off');
    }
    if (bits.isEmpty) return null;
    return bits.join('  \u2022  ');
  }

  @override
  Widget build(BuildContext context) {
    final borderColor =
        selected ? AppColors.onPrimary : AppColors.outline;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: selected
            ? AppColors.primary.withValues(alpha: 0.10)
            : AppColors.surface,
        border: Border.all(
          color: borderColor,
          width: selected ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.onPrimary,
                        borderRadius: BorderRadius.circular(AppRadii.pill),
                      ),
                      child: Text(
                        coupon.code,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 11.5,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _headline,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 13.5,
                      ),
                    ),
                  ],
                ),
                if ((coupon.description ?? '').isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    coupon.description!,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                if (_subline != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    _subline!,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 34,
            child: ElevatedButton(
              onPressed: busy || selected ? null : onApply,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
              child: busy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.onPrimary,
                      ),
                    )
                  : Text(selected ? 'APPLIED' : 'APPLY'),
            ),
          ),
        ],
      ),
    );
  }
}
