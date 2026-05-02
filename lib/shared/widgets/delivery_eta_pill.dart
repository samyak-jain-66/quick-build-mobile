import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

class DeliveryEtaPill extends StatelessWidget {
  const DeliveryEtaPill({
    super.key,
    required this.mode,
    this.etaMin,
    this.etaMax,
  });

  final String mode; // express | same_day | standard | scheduled
  final int? etaMin;
  final int? etaMax;

  String _label() {
    switch (mode) {
      case 'express':
        return 'Express in ${etaMin ?? 10}\u2013${etaMax ?? 30} min';
      case 'same_day':
        return 'Same-day';
      case 'scheduled':
        return 'Scheduled';
      default:
        return 'Standard';
    }
  }

  Color _bg() {
    switch (mode) {
      case 'express':
        return AppColors.primary;
      case 'same_day':
        return AppColors.accent;
      default:
        return AppColors.surfaceAlt;
    }
  }

  Color _fg() {
    switch (mode) {
      case 'express':
        return AppColors.onPrimary;
      case 'same_day':
        return Colors.white;
      default:
        return AppColors.text;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _bg(),
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Text(
        _label(),
        style: TextStyle(
          color: _fg(),
          fontWeight: FontWeight.w800,
          fontSize: 11,
        ),
      ),
    );
  }
}
