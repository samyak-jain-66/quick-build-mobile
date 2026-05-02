import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../shared/models/cart_models.dart';
import '../../theme/app_theme.dart';
import '../cart/cart_repository.dart';
import '../orders/order_payment_service.dart';
import '../orders/orders_repository.dart';
import '../profile/addresses_repository.dart';
import 'buy_now_session.dart';

final _fmt = NumberFormat.currency(
  locale: 'en_IN',
  symbol: '\u20B9',
  decimalDigits: 0,
);

class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});
  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  String? _addressId;
  String _paymentMethod = 'all';
  bool _gstInvoice = false;
  final _gstinCtrl = TextEditingController();
  final _businessNameCtrl = TextEditingController();
  bool _placing = false;

  /// Persisted across retries so a failed/cancelled payment does not spawn
  /// a second `placeOrder` (the first call already cleared the cart, which
  /// made the API reject the retry with a 400).
  String? _currentOrderId;
  String? _currentOrderNumber;

  @override
  void dispose() {
    // If the user backs out of a buy-now checkout before the order is
    // actually placed, drop the session so it doesn't leak into a
    // subsequent navigation to /checkout from the cart tab.
    if (_currentOrderId == null) {
      final container = ProviderScope.containerOf(context, listen: false);
      Future.microtask(
        () => container.read(buyNowSessionProvider.notifier).state = null,
      );
    }
    _gstinCtrl.dispose();
    _businessNameCtrl.dispose();
    super.dispose();
  }

  void _showError(String msg) {
    if (!mounted) return;
    setState(() => _placing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.danger),
    );
  }

  /// Translates the checkout UI's payment choice into a value the backend
  /// `PlaceOrderDto` will accept. `'all'` is a pure UI convenience; stored
  /// on the order as `'upi'` while the Razorpay sheet is opened with no
  /// filter so the buyer can pick any instrument.
  String _dtoPaymentMethod(String uiMethod) {
    switch (uiMethod) {
      case 'all':
        return 'upi';
      default:
        return uiMethod;
    }
  }

  Future<void> _placeCart(CartSummary summary) async {
    if (_addressId == null) {
      _showError('Please select a delivery address');
      return;
    }
    setState(() => _placing = true);
    try {
      final repo = ref.read(ordersRepositoryProvider);

      if (_currentOrderId == null) {
        final order = await repo.placeOrder(
          addressId: _addressId!,
          paymentMethod: _dtoPaymentMethod(_paymentMethod),
          gstInvoice: _gstInvoice,
          gstin: _gstInvoice ? _gstinCtrl.text.trim() : null,
          businessName: _gstInvoice ? _businessNameCtrl.text.trim() : null,
        );
        _currentOrderId = order['id'] as String;
        _currentOrderNumber = order['order_number'] as String? ?? '';
      }

      final payment = ref.read(orderPaymentServiceProvider);
      final result = await payment.payForOrder(
        orderId: _currentOrderId!,
        orderNumber: _currentOrderNumber ?? '',
        amount: summary.grandTotal,
        method: _paymentMethod,
      );
      if (!mounted) return;
      switch (result) {
        case OrderPaymentResult.success:
          await ref.read(cartControllerProvider.notifier).refresh();
          if (!mounted) return;
          context.go('/orders/${_currentOrderId!}');
          return;
        case OrderPaymentResult.cancelled:
          setState(() => _placing = false);
          return;
        case OrderPaymentResult.failed:
          _showError('Payment could not be completed. Please try again.');
          return;
      }
    } catch (e) {
      _showError(e.toString());
    }
  }

  Future<void> _placeBuyNow(BuyNowSession session) async {
    if (_addressId == null) {
      _showError('Please select a delivery address');
      return;
    }
    setState(() => _placing = true);
    try {
      final repo = ref.read(ordersRepositoryProvider);

      if (_currentOrderId == null) {
        final order = await repo.buyNow(
          productId: session.productId,
          quantity: session.quantity,
          addressId: _addressId!,
          paymentMethod: _dtoPaymentMethod(_paymentMethod),
          deliveryMode: session.deliveryMode,
          gstInvoice: _gstInvoice,
          gstin: _gstInvoice ? _gstinCtrl.text.trim() : null,
          businessName: _gstInvoice ? _businessNameCtrl.text.trim() : null,
        );
        _currentOrderId = order['id'] as String;
        _currentOrderNumber = order['order_number'] as String? ?? '';
      }

      final payment = ref.read(orderPaymentServiceProvider);
      final result = await payment.payForOrder(
        orderId: _currentOrderId!,
        orderNumber: _currentOrderNumber ?? '',
        amount: session.grandTotal,
        method: _paymentMethod,
      );
      if (!mounted) return;
      switch (result) {
        case OrderPaymentResult.success:
          // Leave the cart alone (buy-now never read from it) and drop
          // the session so the next /checkout trip re-evaluates.
          ref.read(buyNowSessionProvider.notifier).state = null;
          if (!mounted) return;
          context.go('/orders/${_currentOrderId!}');
          return;
        case OrderPaymentResult.cancelled:
          setState(() => _placing = false);
          return;
        case OrderPaymentResult.failed:
          _showError('Payment could not be completed. Please try again.');
          return;
      }
    } catch (e) {
      _showError(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final buyNow = ref.watch(buyNowSessionProvider);
    if (buyNow != null) {
      return _buildBuyNow(buyNow);
    }
    return _buildCart();
  }

  Widget _buildCart() {
    final cart = ref.watch(cartControllerProvider);
    final addresses = ref.watch(addressesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: cart.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (summary) {
          if (summary == null || summary.groups.isEmpty) {
            return const Center(child: Text('Cart is empty'));
          }
          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const _SectionTitle(title: 'Deliver to'),
                    _AddressPicker(
                      addresses: addresses,
                      selectedId: _addressId,
                      onSelect: (id) => setState(() => _addressId = id),
                    ),
                    const SizedBox(height: 12),
                    const _SectionTitle(title: 'Delivery preview'),
                    for (final g in summary.groups)
                      _CartGroupRow(group: g),
                    const SizedBox(height: 12),
                    _GstSection(
                      enabled: _gstInvoice,
                      gstinCtrl: _gstinCtrl,
                      businessNameCtrl: _businessNameCtrl,
                      onToggle: (v) => setState(() => _gstInvoice = v),
                    ),
                    const SizedBox(height: 16),
                    _PaymentMethodsSection(
                      current: _paymentMethod,
                      onChanged: (v) => setState(() => _paymentMethod = v),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () => context.push('/rfqs'),
                      icon: const Icon(Icons.request_quote_outlined),
                      label: const Text(
                          'Bulk quantity? Request a quote instead'),
                    ),
                  ],
                ),
              ),
              _CheckoutFooter(
                grandTotal: summary.grandTotal,
                loading: _placing,
                onPlace: () => _placeCart(summary),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBuyNow(BuyNowSession session) {
    final addresses = ref.watch(addressesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadii.sm),
                  ),
                  child: Row(
                    children: const [
                      Icon(Icons.flash_on_rounded,
                          size: 18, color: AppColors.text),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Buy now \u2014 this order will only include '
                          'this product. Items in your cart stay put.',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                const _SectionTitle(title: 'Deliver to'),
                _AddressPicker(
                  addresses: addresses,
                  selectedId: _addressId,
                  onSelect: (id) => setState(() => _addressId = id),
                ),
                const SizedBox(height: 12),
                const _SectionTitle(title: 'Item'),
                _BuyNowItemRow(session: session),
                const SizedBox(height: 12),
                _GstSection(
                  enabled: _gstInvoice,
                  gstinCtrl: _gstinCtrl,
                  businessNameCtrl: _businessNameCtrl,
                  onToggle: (v) => setState(() => _gstInvoice = v),
                ),
                const SizedBox(height: 16),
                _PaymentMethodsSection(
                  current: _paymentMethod,
                  onChanged: (v) => setState(() => _paymentMethod = v),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
          _CheckoutFooter(
            grandTotal: session.grandTotal,
            loading: _placing,
            onPlace: () => _placeBuyNow(session),
          ),
        ],
      ),
    );
  }
}

String _deliveryLabelFromMode(
  String mode, {
  required int etaMin,
  required int etaMax,
}) {
  switch (mode) {
    case 'express':
      return 'Express ${etaMin}\u2013${etaMax} min';
    case 'same_day':
      return 'Same-day';
    case 'scheduled':
      return 'Scheduled';
    default:
      return 'Standard delivery';
  }
}

class _AddressPicker extends StatelessWidget {
  const _AddressPicker({
    required this.addresses,
    required this.selectedId,
    required this.onSelect,
  });
  final AsyncValue<List<AddressModel>> addresses;
  final String? selectedId;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    return addresses.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (e, _) => Text('Error: $e'),
      data: (addrs) {
        if (addrs.isEmpty) {
          return OutlinedButton.icon(
            onPressed: () => context.push('/addresses'),
            icon: const Icon(Icons.add_location_alt_outlined),
            label: const Text('Add a delivery address'),
          );
        }
        // Pick a default on first render if caller hasn't set one yet.
        if (selectedId == null) {
          final defaultId = addrs
              .firstWhere((a) => a.isDefault, orElse: () => addrs.first)
              .id;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            onSelect(defaultId);
          });
        }
        return Column(
          children: [
            for (final a in addrs)
              RadioListTile<String>(
                value: a.id,
                groupValue: selectedId,
                onChanged: (v) => onSelect(v),
                contentPadding: EdgeInsets.zero,
                title: Text(
                  a.label ?? 'Address',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text('${a.line1}, ${a.city} ${a.pincode}'),
              ),
            TextButton.icon(
              onPressed: () => context.push('/addresses'),
              icon: const Icon(Icons.add),
              label: const Text('Add new address'),
            ),
          ],
        );
      },
    );
  }
}

class _CartGroupRow extends StatelessWidget {
  const _CartGroupRow({required this.group});
  final CartGroup group;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(AppRadii.sm),
            ),
            child: const Icon(Icons.local_shipping_outlined),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(group.vendorName,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                Text(
                  '${group.items.length} items \u2022 '
                  '${_deliveryLabelFromMode(group.deliveryMode, etaMin: group.etaMinMinutes, etaMax: group.etaMaxMinutes)}',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
          Text(_fmt.format(group.subtotal),
              style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _BuyNowItemRow extends StatelessWidget {
  const _BuyNowItemRow({required this.session});
  final BuyNowSession session;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.outline),
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.sm),
            child: SizedBox(
              width: 62,
              height: 62,
              child: session.image != null
                  ? CachedNetworkImage(
                      imageUrl: session.image!,
                      fit: BoxFit.cover,
                    )
                  : Container(color: AppColors.surfaceAlt),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.productName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  session.vendorName,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${_fmt.format(session.unitPrice)}  \u00D7  ${session.quantity}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _deliveryLabelFromMode(
                    session.deliveryMode,
                    etaMin: session.etaMinMinutes,
                    etaMax: session.etaMaxMinutes,
                  ),
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _fmt.format(session.subtotal),
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _GstSection extends StatelessWidget {
  const _GstSection({
    required this.enabled,
    required this.gstinCtrl,
    required this.businessNameCtrl,
    required this.onToggle,
  });
  final bool enabled;
  final TextEditingController gstinCtrl;
  final TextEditingController businessNameCtrl;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(title: 'GST invoice'),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: enabled,
          onChanged: onToggle,
          title: const Text('I need a GST invoice'),
          subtitle: const Text(
              'Register GSTIN to claim input tax credit'),
        ),
        if (enabled) ...[
          TextField(
            controller: gstinCtrl,
            decoration: const InputDecoration(hintText: 'GSTIN'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: businessNameCtrl,
            decoration: const InputDecoration(
                hintText: 'Registered business name'),
          ),
        ],
      ],
    );
  }
}

class _PaymentMethodsSection extends StatelessWidget {
  const _PaymentMethodsSection({
    required this.current,
    required this.onChanged,
  });
  final String current;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(title: 'Payment method'),
        _PaymentMethodTile(
          value: 'all',
          group: current,
          title: 'All payment options',
          subtitle: 'Let me pick in the checkout window',
          icon: Icons.tune_rounded,
          onChanged: onChanged,
        ),
        _PaymentMethodTile(
          value: 'upi',
          group: current,
          title: 'UPI',
          subtitle: 'Pay via any UPI app',
          icon: Icons.account_balance_wallet_outlined,
          onChanged: onChanged,
        ),
        _PaymentMethodTile(
          value: 'card',
          group: current,
          title: 'Credit / debit card',
          subtitle: 'Visa, Mastercard, RuPay',
          icon: Icons.credit_card,
          onChanged: onChanged,
        ),
        _PaymentMethodTile(
          value: 'netbanking',
          group: current,
          title: 'Net banking',
          subtitle: 'All major banks',
          icon: Icons.account_balance,
          onChanged: onChanged,
        ),
        _PaymentMethodTile(
          value: 'wallet',
          group: current,
          title: 'Wallets',
          subtitle: 'Paytm, PhonePe, Mobikwik, etc.',
          icon: Icons.account_balance_wallet,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});
  final String title;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _PaymentMethodTile extends StatelessWidget {
  const _PaymentMethodTile({
    required this.value,
    required this.group,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onChanged,
  });
  final String value;
  final String group;
  final String title;
  final String subtitle;
  final IconData icon;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = value == group;
    return InkWell(
      onTap: () => onChanged(value),
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: Container(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary.withValues(alpha: 0.15) : null,
          border: Border.all(
            color: selected ? AppColors.onPrimary : AppColors.outline,
            width: selected ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
        child: Row(
          children: [
            Icon(icon, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text(subtitle,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      )),
                ],
              ),
            ),
            Radio<String>(
              value: value,
              groupValue: group,
              onChanged: (v) => v != null ? onChanged(v) : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _CheckoutFooter extends StatelessWidget {
  const _CheckoutFooter({
    required this.grandTotal,
    required this.loading,
    required this.onPlace,
  });
  final double grandTotal;
  final bool loading;
  final VoidCallback onPlace;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 14, 16, MediaQuery.paddingOf(context).bottom + 14),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 18,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Text('To pay',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  )),
              const Spacer(),
              Text(
                _fmt.format(grandTotal),
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: loading ? null : onPlace,
              child: loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: AppColors.onPrimary,
                      ),
                    )
                  : const Text('Place order'),
            ),
          ),
        ],
      ),
    );
  }
}
