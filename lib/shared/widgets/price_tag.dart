import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../theme/app_theme.dart';

class PriceTag extends StatelessWidget {
  const PriceTag({
    super.key,
    required this.price,
    this.basePrice,
    this.discountPct,
    this.compact = false,
  });

  final double price;
  final double? basePrice;
  final double? discountPct;
  final bool compact;

  static final _fmt = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '\u20B9',
    decimalDigits: 0,
  );

  @override
  Widget build(BuildContext context) {
    final hasDiscount = (discountPct ?? 0) > 0 && basePrice != null;
    final priceText = Text(
      _fmt.format(price),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: compact ? 15 : 20,
        fontWeight: FontWeight.w800,
        color: AppColors.text,
      ),
    );

    if (compact) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Flexible(child: priceText),
          if (hasDiscount) ...[
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                _fmt.format(basePrice),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  decoration: TextDecoration.lineThrough,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ],
      );
    }

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      children: [
        priceText,
        if (hasDiscount)
          Text(
            _fmt.format(basePrice),
            style: const TextStyle(
              color: AppColors.textMuted,
              decoration: TextDecoration.lineThrough,
              fontSize: 13,
            ),
          ),
        if (hasDiscount)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${discountPct!.toStringAsFixed(0)}% OFF',
              style: const TextStyle(
                color: AppColors.onPrimary,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
      ],
    );
  }
}
