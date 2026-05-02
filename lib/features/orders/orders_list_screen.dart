import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../theme/app_theme.dart';
import 'order_payment_service.dart';
import 'orders_repository.dart';

final _fmt = NumberFormat.currency(
  locale: 'en_IN',
  symbol: '\u20B9',
  decimalDigits: 0,
);
final _date = DateFormat('dd MMM yyyy \u2022 hh:mm a');

class OrdersListScreen extends ConsumerStatefulWidget {
  const OrdersListScreen({super.key});

  @override
  ConsumerState<OrdersListScreen> createState() => _OrdersListScreenState();
}

class _OrdersListScreenState extends ConsumerState<OrdersListScreen> {
  String? _payingOrderId;

  Future<void> _payForOrder(Map<String, dynamic> order) async {
    if (_payingOrderId != null) return;
    final id = order['id'] as String;
    setState(() => _payingOrderId = id);
    final payment = ref.read(orderPaymentServiceProvider);
    final result = await payment.payForOrder(
      orderId: id,
      orderNumber: order['order_number'] as String? ?? '',
      amount: (order['grand_total'] as num?)?.toDouble() ?? 0,
    );
    if (!mounted) return;
    setState(() => _payingOrderId = null);
    switch (result) {
      case OrderPaymentResult.success:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment successful')),
        );
        ref.invalidate(ordersListProvider);
        ref.invalidate(orderDetailProvider(id));
        break;
      case OrderPaymentResult.failed:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payment could not be verified. Please try again.'),
            backgroundColor: AppColors.danger,
          ),
        );
        break;
      case OrderPaymentResult.cancelled:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(ordersListProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your orders'),
      ),
      body: ordersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (orders) {
          if (orders.isEmpty) {
            return const _EmptyOrders();
          }
          return RefreshIndicator(
            onRefresh: () => ref.refresh(ordersListProvider.future),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: orders.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final o = orders[i];
                return _OrderTile(
                  order: o,
                  paying: _payingOrderId == o['id'],
                  onPay: () => _payForOrder(o),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _OrderTile extends StatelessWidget {
  const _OrderTile({
    required this.order,
    required this.paying,
    required this.onPay,
  });
  final Map<String, dynamic> order;
  final bool paying;
  final VoidCallback onPay;

  @override
  Widget build(BuildContext context) {
    final id = order['id'] as String;
    final number = order['order_number'] as String? ?? id.substring(0, 8);
    final status = (order['status'] as String? ?? 'placed');
    final total = (order['grand_total'] as num?)?.toDouble() ?? 0;
    final items = (order['item_count'] as num?)?.toInt() ??
        ((order['shipments'] as List?)?.length ?? 0);
    final createdRaw = order['created_at'] as String?;
    DateTime? created;
    if (createdRaw != null) {
      created = DateTime.tryParse(createdRaw);
    }
    final isPendingPayment = status == 'pending_payment';
    return InkWell(
      onTap: () => context.push('/orders/$id'),
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(
            color: isPendingPayment
                ? AppColors.warning.withValues(alpha: 0.5)
                : AppColors.outline,
            width: isPendingPayment ? 1.4 : 1,
          ),
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Order #$number',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 15),
                  ),
                ),
                const SizedBox(width: 8),
                _StatusChip(status: status),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              created != null ? _date.format(created) : '',
              style:
                  const TextStyle(color: AppColors.textMuted, fontSize: 12.5),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  items > 0 ? '$items shipment${items == 1 ? '' : 's'}' : '',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                Text(
                  _fmt.format(total),
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 16),
                ),
              ],
            ),
            if (isPendingPayment) ...[
              const SizedBox(height: 12),
              _PayNowInline(
                loading: paying,
                onPay: onPay,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PayNowInline extends StatelessWidget {
  const _PayNowInline({required this.loading, required this.onPay});
  final bool loading;
  final VoidCallback onPay;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadii.sm),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline,
              size: 18, color: AppColors.warning),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Complete payment to confirm this order',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 36,
            child: ElevatedButton.icon(
              onPressed: loading ? null : onPay,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                ),
              ),
              icon: loading
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.onPrimary,
                      ),
                    )
                  : const Icon(Icons.payments_outlined, size: 16),
              label: Text(loading ? 'Opening\u2026' : 'Pay now'),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    switch (status) {
      case 'delivered':
        bg = AppColors.success.withValues(alpha: 0.15);
        fg = AppColors.success;
        break;
      case 'cancelled':
        bg = AppColors.danger.withValues(alpha: 0.12);
        fg = AppColors.danger;
        break;
      case 'pending_payment':
        bg = AppColors.warning.withValues(alpha: 0.18);
        fg = AppColors.warning;
        break;
      case 'out_for_delivery':
      case 'packed':
        bg = AppColors.info.withValues(alpha: 0.12);
        fg = AppColors.info;
        break;
      default:
        bg = AppColors.surfaceAlt;
        fg = AppColors.text;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Text(
        status.replaceAll('_', ' ').toUpperCase(),
        style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _EmptyOrders extends StatelessWidget {
  const _EmptyOrders();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 86,
              height: 86,
              decoration: const BoxDecoration(
                color: AppColors.surfaceAlt,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.receipt_long_outlined, size: 42),
            ),
            const SizedBox(height: 16),
            const Text(
              'No orders yet',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            const Text(
              'Your orders will appear here once you place your first one.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => context.go('/'),
              child: const Text('Start shopping'),
            ),
          ],
        ),
      ),
    );
  }
}
