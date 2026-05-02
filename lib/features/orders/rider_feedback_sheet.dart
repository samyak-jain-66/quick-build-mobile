import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_theme.dart';
import 'orders_repository.dart';
import 'tracking_repository.dart';

/// Modal bottom sheet for collecting rider feedback. Five-star tappable
/// row + optional 500-char comment + Submit. Posts to
/// `POST /orders/:id/rider-feedback`; on success it invalidates
/// `orderTrackingProvider` so the caller's rider card flips to "You
/// rated this rider".
class RiderFeedbackSheet extends ConsumerStatefulWidget {
  const RiderFeedbackSheet({
    super.key,
    required this.orderId,
    required this.riderName,
  });

  final String orderId;
  final String riderName;

  /// Convenience launcher that wraps `showModalBottomSheet`.
  static Future<bool?> show(
    BuildContext context, {
    required String orderId,
    required String riderName,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          RiderFeedbackSheet(orderId: orderId, riderName: riderName),
    );
  }

  @override
  ConsumerState<RiderFeedbackSheet> createState() =>
      _RiderFeedbackSheetState();
}

class _RiderFeedbackSheetState extends ConsumerState<RiderFeedbackSheet> {
  int _stars = 5;
  final _commentCtrl = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(ordersRepositoryProvider).submitRiderFeedback(
            widget.orderId,
            rating: _stars,
            comment: _commentCtrl.text.trim().isEmpty
                ? null
                : _commentCtrl.text.trim(),
          );
      if (!mounted) return;
      ref.invalidate(orderTrackingProvider(widget.orderId));
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Thanks for the feedback!')),
      );
    } catch (e) {
      String msg;
      if (e is DioException) {
        final body = e.response?.data;
        if (e.response?.statusCode == 409) {
          msg = 'You have already rated this rider.';
        } else if (body is Map && body['message'] is String) {
          msg = body['message'] as String;
        } else {
          msg = 'Could not submit feedback. Please try again.';
        }
      } else {
        msg = 'Could not submit feedback. Please try again.';
      }
      if (mounted) setState(() => _error = msg);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(AppRadii.lg)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.outline,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'How was your delivery?',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  'Rate ${widget.riderName} for this order',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(5, (i) {
                    final filled = _stars >= i + 1;
                    return GestureDetector(
                      onTap: _submitting
                          ? null
                          : () => setState(() => _stars = i + 1),
                      child: Icon(
                        filled ? Icons.star_rounded : Icons.star_outline_rounded,
                        size: 44,
                        color: filled ? AppColors.primary : AppColors.outline,
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: _commentCtrl,
                  enabled: !_submitting,
                  maxLines: 3,
                  maxLength: 500,
                  decoration: const InputDecoration(
                    hintText: 'Share what went well or could be better (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: const TextStyle(color: AppColors.danger, fontSize: 13),
                  ),
                ],
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _submitting ? null : _submit,
                    child: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.onPrimary,
                            ),
                          )
                        : const Text('Submit feedback'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
