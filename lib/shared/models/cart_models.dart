class CartItem {
  CartItem({
    required this.id,
    required this.productId,
    required this.name,
    required this.image,
    required this.vendorId,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
    required this.deliveryMode,
    required this.moq,
  });

  final String id;
  final String productId;
  final String name;
  final String? image;
  final String vendorId;
  final int quantity;
  final double unitPrice;
  final double lineTotal;
  final String deliveryMode;
  final int moq;

  factory CartItem.fromJson(Map<String, dynamic> json) => CartItem(
        id: json['id'] as String,
        productId: json['product_id'] as String,
        name: json['name'] as String? ?? '',
        image: json['image'] as String?,
        vendorId: json['vendor_id'] as String,
        quantity: (json['quantity'] as num).toInt(),
        unitPrice: (json['unit_price'] as num).toDouble(),
        lineTotal: (json['line_total'] as num).toDouble(),
        deliveryMode: json['delivery_mode'] as String? ?? 'standard',
        moq: (json['moq'] as num?)?.toInt() ?? 1,
      );
}

class CartGroup {
  CartGroup({
    required this.vendorId,
    required this.vendorName,
    required this.deliveryMode,
    required this.etaMinMinutes,
    required this.etaMaxMinutes,
    required this.items,
    required this.subtotal,
  });

  final String vendorId;
  final String vendorName;
  final String deliveryMode;
  final int etaMinMinutes;
  final int etaMaxMinutes;
  final List<CartItem> items;
  final double subtotal;

  factory CartGroup.fromJson(Map<String, dynamic> json) => CartGroup(
        vendorId: json['vendor_id'] as String,
        vendorName: json['vendor_name'] as String? ?? 'Vendor',
        deliveryMode: json['delivery_mode'] as String? ?? 'standard',
        etaMinMinutes: (json['eta_min_minutes'] as num?)?.toInt() ?? 0,
        etaMaxMinutes: (json['eta_max_minutes'] as num?)?.toInt() ?? 0,
        items: ((json['items'] as List?) ?? const [])
            .map((e) => CartItem.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0,
      );
}

class CartSummary {
  CartSummary({
    required this.cartId,
    required this.couponCode,
    required this.useWallet,
    required this.notes,
    required this.groups,
    required this.subtotal,
    required this.discountTotal,
    required this.taxTotal,
    required this.shippingTotal,
    required this.grandTotal,
  });

  final String cartId;
  final String? couponCode;
  final bool useWallet;
  final String? notes;
  final List<CartGroup> groups;
  final double subtotal;
  final double discountTotal;
  final double taxTotal;
  final double shippingTotal;
  final double grandTotal;

  int get totalItems =>
      groups.fold<int>(0, (acc, g) => acc + g.items.fold<int>(0, (a, i) => a + i.quantity));

  factory CartSummary.fromJson(Map<String, dynamic> json) => CartSummary(
        cartId: json['cart_id'] as String,
        couponCode: json['coupon_code'] as String?,
        useWallet: (json['use_wallet'] as bool?) ?? false,
        notes: json['notes'] as String?,
        groups: ((json['groups'] as List?) ?? const [])
            .map((e) => CartGroup.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0,
        discountTotal: (json['discount_total'] as num?)?.toDouble() ?? 0,
        taxTotal: (json['tax_total'] as num?)?.toDouble() ?? 0,
        shippingTotal: (json['shipping_total'] as num?)?.toDouble() ?? 0,
        grandTotal: (json['grand_total'] as num?)?.toDouble() ?? 0,
      );
}
