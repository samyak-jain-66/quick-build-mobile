import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_theme.dart';
import 'orders_repository.dart';
import 'tracking_repository.dart';

/// Lightweight DTO for the rating sheet's input. Decoupled from the
/// order_items JSON shape so callers can pass whatever they have.
class OrderItemForRating {
  const OrderItemForRating({
    required this.productId,
    required this.name,
    this.imageUrl,
  });
  final String productId;
  final String name;
  final String? imageUrl;
}

/// Modal bottom sheet that lists every product in the order with its
/// own 5-star selector + optional comment. Submit POSTs one review per
/// rated product (skipping already-rated ones via the seed list and
/// silently swallowing 4xx duplicate-key responses).
class OrderRatingSheet extends ConsumerStatefulWidget {
  const OrderRatingSheet({
    super.key,
    required this.orderId,
    required this.items,
  });

  final String orderId;
  final List<OrderItemForRating> items;

  static Future<bool?> show(
    BuildContext context, {
    required String orderId,
    required List<OrderItemForRating> items,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => OrderRatingSheet(orderId: orderId, items: items),
    );
  }

  @override
  ConsumerState<OrderRatingSheet> createState() => _OrderRatingSheetState();
}

class _OrderRatingSheetState extends ConsumerState<OrderRatingSheet> {
  /// productId -> rating already in DB. Read-only; rendered as a locked row.
  final Map<String, int> _existing = {};
  /// productId -> currently-selected rating in this session (1-5, 0 = unset).
  final Map<String, int> _selected = {};
  /// productId -> ephemeral comment text.
  final Map<String, TextEditingController> _comments = {};

  bool _loading = true;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final item in widget.items) {
      _comments[item.productId] = TextEditingController();
    }
    _loadExisting();
  }

  @override
  void dispose() {
    for (final c in _comments.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadExisting() async {
    try {
      final rows = await ref
          .read(ordersRepositoryProvider)
          .myReviewsForOrder(widget.orderId);
      if (!mounted) return;
      setState(() {
        for (final row in rows) {
          final pid = row['product_id'] as String?;
          final rating = (row['rating'] as num?)?.toInt();
          if (pid != null && rating != null) {
            _existing[pid] = rating;
          }
        }
        _loading = false;
      });
    } catch (_) {
      // Non-fatal: worst case the user can submit and hit a 4xx duplicate;
      // we surface that nicely below.
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final pendingPids = widget.items
        .map((i) => i.productId)
        .where((pid) =>
            !_existing.containsKey(pid) && (_selected[pid] ?? 0) > 0)
        .toList();
    if (pendingPids.isEmpty) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });

    final repo = ref.read(ordersRepositoryProvider);
    int successes = 0;
    final failures = <String>[];
    for (final pid in pendingPids) {
      try {
        await repo.submitProductReview(
          productId: pid,
          orderId: widget.orderId,
          rating: _selected[pid]!,
          body: _comments[pid]?.text.trim().isEmpty == true
              ? null
              : _comments[pid]?.text.trim(),
        );
        successes++;
      } on DioException catch (e) {
        // Duplicate (409 / unique violation) is a benign no-op; anything
        // else we surface so the user knows what failed.
        if (e.response?.statusCode == 409 ||
            (e.response?.data is Map &&
                ((e.response!.data as Map)['message'] is String) &&
                ((e.response!.data as Map)['message'] as String)
                    .toLowerCase()
                    .contains('duplicate'))) {
          continue;
        }
        failures.add(pid);
      } catch (_) {
        failures.add(pid);
      }
    }

    if (!mounted) return;
    setState(() => _submitting = false);

    if (failures.isEmpty) {
      // Make the screen pick up the new "rated" state.
      ref.invalidate(orderTrackingProvider(widget.orderId));
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            successes <= 1
                ? 'Thanks for the rating!'
                : 'Thanks for rating $successes products',
          ),
        ),
      );
    } else {
      setState(() {
        _error = 'Could not save ${failures.length} rating'
            '${failures.length == 1 ? '' : 's'}. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(AppRadii.lg)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.outline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Rate the products',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Tap stars to rate each product. Already rated items are locked.',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.all(28),
                    child: CircularProgressIndicator(),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                      itemCount: widget.items.length,
                      separatorBuilder: (_, __) => const Divider(
                        height: 24,
                        color: AppColors.outline,
                      ),
                      itemBuilder: (_, i) => _Row(
                        item: widget.items[i],
                        existingRating: _existing[widget.items[i].productId],
                        selectedRating:
                            _selected[widget.items[i].productId] ?? 0,
                        comment: _comments[widget.items[i].productId]!,
                        enabled: !_submitting,
                        onSelect: (r) => setState(
                            () => _selected[widget.items[i].productId] = r),
                      ),
                    ),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        color: AppColors.danger,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                  child: SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _loading || _submitting ? null : _submit,
                      child: _submitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.onPrimary,
                              ),
                            )
                          : const Text('Submit ratings'),
                    ),
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

class _Row extends StatelessWidget {
  const _Row({
    required this.item,
    required this.existingRating,
    required this.selectedRating,
    required this.comment,
    required this.enabled,
    required this.onSelect,
  });

  final OrderItemForRating item;
  final int? existingRating;
  final int selectedRating;
  final TextEditingController comment;
  final bool enabled;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final isLocked = existingRating != null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.sm),
          child: SizedBox(
            width: 56,
            height: 56,
            child: (item.imageUrl != null && item.imageUrl!.isNotEmpty)
                ? CachedNetworkImage(
                    imageUrl: item.imageUrl!,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => const _ImageFallback(),
                    placeholder: (_, __) => const _ImageFallback(),
                  )
                : const _ImageFallback(),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
              ),
              const SizedBox(height: 6),
              Row(
                children: List.generate(5, (i) {
                  final n = i + 1;
                  final filled =
                      (isLocked ? existingRating! : selectedRating) >= n;
                  return GestureDetector(
                    onTap: (isLocked || !enabled) ? null : () => onSelect(n),
                    child: Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Icon(
                        filled
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        size: 26,
                        color: filled ? AppColors.primary : AppColors.outline,
                      ),
                    ),
                  );
                }),
              ),
              if (isLocked)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    'You already rated this product',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                  ),
                )
              else if (selectedRating > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: TextField(
                    controller: comment,
                    enabled: enabled,
                    minLines: 1,
                    maxLines: 3,
                    maxLength: 500,
                    decoration: const InputDecoration(
                      hintText: 'Add a short comment (optional)',
                      isDense: true,
                      border: OutlineInputBorder(),
                      counterText: '',
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ImageFallback extends StatelessWidget {
  const _ImageFallback();
  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surfaceAlt,
      child: const Icon(
        Icons.inventory_2_outlined,
        size: 22,
        color: AppColors.textMuted,
      ),
    );
  }
}
