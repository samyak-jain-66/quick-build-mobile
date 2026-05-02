import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_theme.dart';
import 'location_models.dart';
import 'location_sheet.dart';
import 'notify_me_sheet.dart';

/// Replaces the home feed when the user's chosen pincode isn't serviceable.
/// Offers two CTAs: join the waitlist for their area, or change the
/// pincode to one we do serve.
class NotServiceableView extends ConsumerWidget {
  const NotServiceableView({super.key, required this.location});
  final ServiceableLocation location;

  Future<void> _openNotifyMe(BuildContext context) async {
    final joined = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => NotifyMeSheet(pincode: location.pincode),
    );
    if (!context.mounted) return;
    if (joined == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Thanks! We'll email and text you the day we launch in your area.",
          ),
        ),
      );
    }
  }

  Future<void> _openLocationSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const LocationSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      top: false,
      child: LayoutBuilder(
        builder: (_, constraints) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 92,
                      height: 92,
                      decoration: BoxDecoration(
                        color:
                            AppColors.warning.withValues(alpha: 0.14),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.explore_off_rounded,
                        color: AppColors.warning,
                        size: 44,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    "We're not in your area yet",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Quick-Build is live in Gurugram, Manesar & Sohna. '
                    "We'll be knocking on ${location.pincode} very soon.",
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Container(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.10),
                      border: Border.all(
                        color:
                            AppColors.onPrimary.withValues(alpha: 0.45),
                      ),
                      borderRadius:
                          BorderRadius.circular(AppRadii.md),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: const BoxDecoration(
                                color: AppColors.onPrimary,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.campaign_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                'Get a heads-up on launch day',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Leave your name, phone and email. No spam '
                          '\u2014 just one message the day we go live.',
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 46,
                          child: ElevatedButton.icon(
                            onPressed: () => _openNotifyMe(context),
                            icon: const Icon(
                                Icons.notifications_active_rounded,
                                size: 18),
                            label: const Text('Notify me when we launch'),
                            style: ElevatedButton.styleFrom(
                              textStyle: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 13.5,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 46,
                    child: OutlinedButton.icon(
                      onPressed: () => _openLocationSheet(context),
                      icon: const Icon(
                          Icons.edit_location_alt_outlined, size: 18),
                      label: const Text('Change location'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
