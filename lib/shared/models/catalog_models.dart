class CategoryNode {
  CategoryNode({
    required this.id,
    required this.name,
    required this.slug,
    required this.parentId,
    required this.iconUrl,
    required this.sortOrder,
    required this.children,
  });

  final String id;
  final String name;
  final String slug;
  final String? parentId;
  final String? iconUrl;
  final int sortOrder;
  final List<CategoryNode> children;

  factory CategoryNode.fromJson(Map<String, dynamic> json) {
    final raw = (json['children'] as List?) ?? const [];
    return CategoryNode(
      id: json['id'] as String,
      name: json['name'] as String,
      slug: json['slug'] as String,
      parentId: json['parent_id'] as String?,
      iconUrl: json['icon_url'] as String?,
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      children: raw
          .map((e) => CategoryNode.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}

class ProductSummary {
  ProductSummary({
    required this.id,
    required this.sku,
    required this.slug,
    required this.name,
    required this.shortDescription,
    required this.basePrice,
    required this.displayPrice,
    required this.discountPct,
    required this.moq,
    required this.images,
    required this.brandName,
    required this.vendorName,
    required this.vendorRating,
    required this.categoryName,
    required this.expressEligible,
  });

  final String id;
  final String sku;
  final String slug;
  final String name;
  final String? shortDescription;
  final double basePrice;
  final double displayPrice;
  final double discountPct;
  final int moq;
  final List<String> images;
  final String? brandName;
  final String? vendorName;
  final double vendorRating;
  final String? categoryName;
  final bool expressEligible;

  factory ProductSummary.fromJson(Map<String, dynamic> json) {
    final brand = json['brands'] as Map?;
    final vendor = json['vendors'] as Map?;
    final category = json['categories'] as Map?;
    return ProductSummary(
      id: json['id'] as String,
      sku: (json['sku'] as String?) ?? '',
      slug: json['slug'] as String,
      name: json['name'] as String,
      shortDescription: json['short_description'] as String?,
      basePrice: (json['base_price'] as num?)?.toDouble() ?? 0,
      displayPrice: (json['display_price'] as num?)?.toDouble() ??
          (json['base_price'] as num?)?.toDouble() ??
          0,
      discountPct: (json['discount_pct'] as num?)?.toDouble() ?? 0,
      moq: (json['moq'] as num?)?.toInt() ?? 1,
      images: ((json['images'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
      brandName: brand?['name'] as String?,
      vendorName: vendor?['name'] as String?,
      vendorRating: (vendor?['rating'] as num?)?.toDouble() ?? 0,
      categoryName: category?['name'] as String?,
      expressEligible: (json['is_express_eligible'] as bool?) ?? true,
    );
  }
}

class BulkPricingTier {
  BulkPricingTier({required this.minQty, required this.price});
  final int minQty;
  final double price;
  factory BulkPricingTier.fromJson(Map<String, dynamic> json) =>
      BulkPricingTier(
        minQty: (json['min_qty'] as num).toInt(),
        price: (json['price'] as num).toDouble(),
      );
}

class ProductDetail {
  ProductDetail({
    required this.id,
    required this.sku,
    required this.slug,
    required this.name,
    required this.description,
    required this.shortDescription,
    required this.basePrice,
    required this.displayPrice,
    required this.discountPct,
    required this.taxPct,
    required this.moq,
    required this.unit,
    required this.images,
    required this.videos,
    required this.model3dUrl,
    required this.specs,
    required this.tiers,
    required this.expressEligible,
    required this.brandName,
    required this.vendorId,
    required this.vendorName,
    required this.vendorRating,
    required this.categoryName,
    required this.categorySlug,
  });

  final String id;
  final String sku;
  final String slug;
  final String name;
  final String? description;
  final String? shortDescription;
  final double basePrice;
  final double displayPrice;
  final double discountPct;
  final double taxPct;
  final int moq;
  final String unit;
  final List<String> images;
  final List<String> videos;
  final String? model3dUrl;
  final Map<String, dynamic> specs;
  final List<BulkPricingTier> tiers;
  final bool expressEligible;
  final String? brandName;
  final String vendorId;
  final String? vendorName;
  final double vendorRating;
  final String? categoryName;
  final String? categorySlug;

  factory ProductDetail.fromJson(Map<String, dynamic> json) {
    final brand = json['brands'] as Map?;
    final vendor = json['vendors'] as Map?;
    final category = json['categories'] as Map?;
    final tiers = ((json['bulk_pricing_tiers'] as List?) ?? const [])
        .map((e) => BulkPricingTier.fromJson(Map<String, dynamic>.from(e)))
        .toList()
      ..sort((a, b) => a.minQty.compareTo(b.minQty));
    return ProductDetail(
      id: json['id'] as String,
      sku: (json['sku'] as String?) ?? '',
      slug: json['slug'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      shortDescription: json['short_description'] as String?,
      basePrice: (json['base_price'] as num?)?.toDouble() ?? 0,
      displayPrice: (json['display_price'] as num?)?.toDouble() ??
          (json['base_price'] as num?)?.toDouble() ??
          0,
      discountPct: (json['discount_pct'] as num?)?.toDouble() ?? 0,
      taxPct: (json['tax_pct'] as num?)?.toDouble() ?? 0,
      moq: (json['moq'] as num?)?.toInt() ?? 1,
      unit: (json['unit'] as String?) ?? 'pc',
      images: ((json['images'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
      videos: ((json['videos'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
      model3dUrl: json['model_3d_url'] as String?,
      specs: Map<String, dynamic>.from((json['specs'] as Map?) ?? const {}),
      tiers: tiers,
      expressEligible: (json['is_express_eligible'] as bool?) ?? true,
      brandName: brand?['name'] as String?,
      vendorId: (vendor?['id'] as String?) ?? (json['vendor_id'] as String? ?? ''),
      vendorName: vendor?['name'] as String?,
      vendorRating: (vendor?['rating'] as num?)?.toDouble() ?? 0,
      categoryName: category?['name'] as String?,
      categorySlug: category?['slug'] as String?,
    );
  }
}
