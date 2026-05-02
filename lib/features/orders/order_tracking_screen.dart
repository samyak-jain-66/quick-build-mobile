import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/env/app_env.dart';
import '../../theme/app_theme.dart';
import 'order_payment_service.dart';
import 'order_rating_sheet.dart';
import 'orders_repository.dart';
import 'rider_feedback_sheet.dart';
import 'tracking_repository.dart';

final _fmt = NumberFormat.currency(
  locale: 'en_IN',
  symbol: '\u20B9',
  decimalDigits: 0,
);

class OrderTrackingScreen extends ConsumerStatefulWidget {
  const OrderTrackingScreen({super.key, required this.orderId});
  final String orderId;

  @override
  ConsumerState<OrderTrackingScreen> createState() =>
      _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends ConsumerState<OrderTrackingScreen> {
  RealtimeChannel? _channel;
  GoogleMapController? _mapController;
  /// Last known rider position. Seeded from `tracking.currentLocation`
  /// on first load, then overwritten by realtime `location` broadcasts
  /// every ~5s while the rider is on the road.
  LatLng? _partnerLatLng;
  /// ETA pulled from realtime broadcasts. Falls back to the polled value
  /// in the tracking response when we haven't received a tick yet.
  int? _liveEtaMin;
  /// Position the camera was last animated to. Used to suppress small
  /// jitters - we only re-pan when the rider has moved more than a few
  /// metres from the previous animated position.
  LatLng? _lastAnimatedTo;
  /// Periodic refresh while the screen is mounted. Backstop for cases
  /// where Supabase Realtime broadcasts don't reach the client - polling
  /// is the source of truth, realtime is just a low-latency optimization.
  Timer? _pollTimer;
  bool _payingNow = false;
  bool _hasFramedCamera = false;

  @override
  void initState() {
    super.initState();
    _subscribeRealtime();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      ref.invalidate(orderTrackingProvider(widget.orderId));
      ref.invalidate(orderDetailProvider(widget.orderId));
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _channel?.unsubscribe();
    _mapController?.dispose();
    super.dispose();
  }

  void _subscribeRealtime() {
    if (!AppEnv.isConfigured) return;
    final supabase = ref.read(supabaseClientProvider);
    _channel = supabase.channel('order:${widget.orderId}')
      ..onBroadcast(
        event: 'location',
        callback: (payload) {
          final lat = (payload['lat'] as num?)?.toDouble();
          final lng = (payload['lng'] as num?)?.toDouble();
          final eta = (payload['eta_remaining_min'] as num?)?.toInt();
          if (lat != null && lng != null) {
            _movePartner(LatLng(lat, lng), eta);
          }
        },
      )
      ..onBroadcast(
        event: 'status',
        callback: (payload) {
          // Refresh both detail (for the timeline) and tracking (for the
          // newly-assigned rider, status, and any cached polyline).
          ref.invalidate(orderDetailProvider(widget.orderId));
          ref.invalidate(orderTrackingProvider(widget.orderId));
        },
      )
      ..subscribe();
  }

  /// Updates the rider marker and (if the new position is meaningfully
  /// different from the last one we panned to) animates the camera.
  /// Shared by the realtime broadcast handler and the polling-driven
  /// tracking refresh so they don't fight each other.
  void _movePartner(LatLng next, int? etaRemainingMin) {
    if (!mounted) return;
    final prev = _partnerLatLng;
    if (prev != null &&
        prev.latitude == next.latitude &&
        prev.longitude == next.longitude) {
      // No-op repaint; still update ETA in case it moved.
      if (etaRemainingMin != null && etaRemainingMin != _liveEtaMin) {
        setState(() => _liveEtaMin = etaRemainingMin);
      }
      return;
    }
    setState(() {
      _partnerLatLng = next;
      if (etaRemainingMin != null) _liveEtaMin = etaRemainingMin;
    });
    final last = _lastAnimatedTo;
    if (last == null || _distanceMetres(last, next) > 50) {
      _mapController?.animateCamera(CameraUpdate.newLatLng(next));
      _lastAnimatedTo = next;
    }
  }

  /// Flattens shipments -> order_items into the lightweight DTO the
  /// rating sheet expects. De-duplicates by product_id so the sheet
  /// asks for one rating per product even when multiple shipments
  /// contain the same SKU.
  /// Collapses shipments by vendor_id so the user sees one row per
  /// vendor on the Shipments list. Item count is summed; delivery_mode
  /// becomes a comma-joined list of distinct modes; status picks the
  /// least-progressed shipment in the group (so a mixed group with one
  /// out_for_delivery and one delivered shows "out_for_delivery"
  /// because there's still something to wait for). Cancelled has the
  /// lowest rank so a partially-cancelled vendor surfaces that hint.
  List<Map<String, dynamic>> _groupShipmentsByVendor(List<dynamic> shipments) {
    const statusRank = {
      'cancelled': 0,
      'pending_payment': 1,
      'placed': 2,
      'confirmed': 3,
      'packed': 4,
      'out_for_delivery': 5,
      'delivered': 6,
    };

    final groups = <String, Map<String, dynamic>>{};
    for (final raw in shipments) {
      final s = (raw as Map).cast<String, dynamic>();
      final vendorId = (s['vendor_id'] as String?) ?? 'unknown';

      final orderItems = (s['order_items'] as List?) ?? const <dynamic>[];
      final itemCount =
          (s['item_count'] as num?)?.toInt() ?? orderItems.length;
      final mode = (s['delivery_mode'] as String?) ?? 'standard';
      final status = (s['status'] as String?) ?? 'placed';

      final existing = groups[vendorId];
      if (existing == null) {
        groups[vendorId] = {
          ...s,
          'item_count': itemCount,
          'delivery_mode': mode,
          'status': status,
          '__modes': <String>{mode},
          '__rank': statusRank[status] ?? 99,
        };
        continue;
      }

      existing['item_count'] = (existing['item_count'] as int) + itemCount;
      final modes = (existing['__modes'] as Set<String>)..add(mode);
      final sortedModes = modes.toList()..sort();
      existing['delivery_mode'] = sortedModes.join(', ');

      final rank = statusRank[status] ?? 99;
      if (rank < (existing['__rank'] as int)) {
        existing['status'] = status;
        existing['__rank'] = rank;
      }
    }

    return groups.values.map((m) {
      m.remove('__modes');
      m.remove('__rank');
      return m;
    }).toList();
  }

  List<OrderItemForRating> _itemsForRating(List<dynamic> shipments) {
    final seen = <String>{};
    final out = <OrderItemForRating>[];
    for (final raw in shipments) {
      final ship = (raw as Map).cast<String, dynamic>();
      final items = (ship['order_items'] as List?) ?? const <dynamic>[];
      for (final it in items) {
        final m = (it as Map).cast<String, dynamic>();
        final pid = m['product_id'] as String?;
        if (pid == null || !seen.add(pid)) continue;
        final products = (m['products'] as Map?)?.cast<String, dynamic>();
        final images = (products?['images'] as List?)?.cast<dynamic>();
        final firstImage = (images != null && images.isNotEmpty)
            ? images.first as String?
            : null;
        out.add(OrderItemForRating(
          productId: pid,
          name: (m['name'] as String?) ?? 'Product',
          imageUrl: firstImage,
        ));
      }
    }
    return out;
  }

  /// Equirectangular approximation - good to ~0.1% over urban distances
  /// and faster than the full Haversine. We only use it to compare 5-second
  /// rider hops, so a few metres of error is fine.
  double _distanceMetres(LatLng a, LatLng b) {
    const earthRadiusM = 6371000.0;
    final lat1 = a.latitude * math.pi / 180;
    final lat2 = b.latitude * math.pi / 180;
    final dLat = lat2 - lat1;
    final dLng = (b.longitude - a.longitude) * math.pi / 180;
    final x = dLng * math.cos((lat1 + lat2) / 2);
    return earthRadiusM * math.sqrt(dLat * dLat + x * x);
  }

  Future<void> _callRider(String phone) async {
    final uri = Uri.parse('tel:${phone.replaceAll(' ', '')}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start call to $phone')),
      );
    }
  }

  void _frameMapTo(OrderTracking tracking) {
    final controller = _mapController;
    if (controller == null || _hasFramedCamera) return;
    final dest = tracking.destination;
    final wh = tracking.warehouse;
    if (dest == null) return;
    if (wh != null) {
      final bounds = _boundsFor([wh, dest, if (_partnerLatLng != null) _partnerLatLng!]);
      controller.animateCamera(CameraUpdate.newLatLngBounds(bounds, 64));
    } else {
      controller.animateCamera(CameraUpdate.newLatLngZoom(dest, 14));
    }
    _hasFramedCamera = true;
  }

  LatLngBounds _boundsFor(List<LatLng> points) {
    double? minLat, minLng, maxLat, maxLng;
    for (final p in points) {
      minLat = minLat == null ? p.latitude : (p.latitude < minLat ? p.latitude : minLat);
      maxLat = maxLat == null ? p.latitude : (p.latitude > maxLat ? p.latitude : maxLat);
      minLng = minLng == null ? p.longitude : (p.longitude < minLng ? p.longitude : minLng);
      maxLng = maxLng == null ? p.longitude : (p.longitude > maxLng ? p.longitude : maxLng);
    }
    return LatLngBounds(
      southwest: LatLng(minLat!, minLng!),
      northeast: LatLng(maxLat!, maxLng!),
    );
  }

  Future<void> _payNow(Map<String, dynamic> order) async {
    if (_payingNow) return;
    setState(() => _payingNow = true);
    final payment = ref.read(orderPaymentServiceProvider);
    final result = await payment.payForOrder(
      orderId: order['id'] as String,
      orderNumber: order['order_number'] as String? ?? '',
      amount: (order['grand_total'] as num?)?.toDouble() ?? 0,
    );
    if (!mounted) return;
    setState(() => _payingNow = false);
    if (result == OrderPaymentResult.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment successful')),
      );
      ref.invalidate(ordersListProvider);
      ref.invalidate(orderDetailProvider(widget.orderId));
    } else if (result == OrderPaymentResult.failed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Payment could not be verified. Please try again.'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(orderDetailProvider(widget.orderId));
    final trackingAsync = ref.watch(orderTrackingProvider(widget.orderId));

    // When fresh tracking data lands, seed the rider position + ETA from
    // it (so the map has something to show before the first realtime tick
    // arrives). Done in a listener to avoid mutating state inside build().
    ref.listen<AsyncValue<OrderTracking>>(
      orderTrackingProvider(widget.orderId),
      (prev, next) {
        next.whenData((t) {
          if (!mounted) return;
          // Polling is the source of truth: every 5s tracking refresh
          // should be allowed to overwrite the rider's last known
          // position + ETA, otherwise the rider freezes on whatever the
          // first response set. Realtime broadcasts may still beat us to
          // it - that's fine, _movePartner is idempotent on equal coords.
          if (t.currentLocation != null) {
            _movePartner(t.currentLocation!, t.etaMinutes);
          } else if (t.etaMinutes != null && t.etaMinutes != _liveEtaMin) {
            setState(() => _liveEtaMin = t.etaMinutes);
          }
        });
      },
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Track order')),
      body: detailAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (order) {
          final shipments =
              (order['shipments'] as List?) ?? const <dynamic>[];
          final tracking = trackingAsync.asData?.value;
          final orderStatus = (order['status'] as String?) ?? 'placed';
          // Use the shipment status as the source of truth for the visible
          // status (header / timeline / rider card / rate CTA). The order
          // row only flips to 'delivered' when ALL shipments are delivered
          // and never sees 'packed' / 'out_for_delivery' on its own.
          // Carve-outs: pending_payment exists before any shipment is
          // created, and cancelled is order-level by design.
          final status = (orderStatus == 'pending_payment' ||
                  orderStatus == 'cancelled')
              ? orderStatus
              : (tracking?.status ?? orderStatus);
          final total = (order['grand_total'] as num?)?.toDouble() ?? 0;
          final number = order['order_number'] as String? ?? '';
          // The Supabase query aliases the FK as `addresses`, but some paths
          // historically used `address` — accept either.
          final addr = (order['addresses'] as Map?)?.cast<String, dynamic>() ??
              (order['address'] as Map?)?.cast<String, dynamic>();

          final showMap = tracking != null &&
              tracking.isLive &&
              tracking.destination != null;
          final etaForDisplay = _liveEtaMin ?? tracking?.etaMinutes;
          final rider = tracking?.rider;

          final isPendingPayment = status == 'pending_payment';

          return Stack(
            children: [
              RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(orderTrackingProvider(widget.orderId));
                  await ref
                      .refresh(orderDetailProvider(widget.orderId).future);
                },
                child: ListView(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    16,
                    16,
                    isPendingPayment ? 120 : 16,
                  ),
                  children: [
                    _HeaderCard(
                      number: number,
                      status: status,
                      total: total,
                    ),
                    if (isPendingPayment) ...[
                      const SizedBox(height: 12),
                      _PendingPaymentCard(
                        total: total,
                        loading: _payingNow,
                        onPay: () => _payNow(order),
                      ),
                    ],
                    if (showMap) ...[
                      const SizedBox(height: 16),
                      _LiveMap(
                        tracking: tracking,
                        partner: _partnerLatLng,
                        etaMinutes: etaForDisplay,
                        onMapCreated: (c) {
                          _mapController = c;
                          _frameMapTo(tracking);
                        },
                      ),
                    ],
                    if (rider != null && status == 'out_for_delivery') ...[
                      const SizedBox(height: 12),
                      _RiderCard(
                        rider: rider,
                        etaMinutes: etaForDisplay,
                        onCall: () => _callRider(rider.phone),
                      ),
                    ],
                    if (rider != null && status == 'delivered') ...[
                      const SizedBox(height: 12),
                      _RateRiderCta(
                        feedbackSubmitted:
                            tracking?.feedbackSubmitted ?? false,
                        onRate: () => RiderFeedbackSheet.show(
                          context,
                          orderId: widget.orderId,
                          riderName: rider.name,
                        ),
                      ),
                    ],
                    if (status == 'delivered') ...[
                      const SizedBox(height: 16),
                      const _DeliveredBanner(),
                      const SizedBox(height: 12),
                      _RateOrderCta(
                        orderId: widget.orderId,
                        items: _itemsForRating(shipments),
                      ),
                    ],
                    const SizedBox(height: 16),
                    _Timeline(status: status),
                    if (shipments.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const Text('Shipments',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      // Collapse same-vendor shipments into one tile.
                      // The receipt-style Items list below still shows
                      // every product line individually.
                      for (final s in _groupShipmentsByVendor(shipments))
                        _ShipmentTile(shipment: s),
                    ],
                    // Items + summary always render once a shipment exists
                    // (even before delivery), so the user sees what they
                    // ordered and how much they paid.
                    if (shipments.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _OrderItemsList(shipments: shipments),
                      const SizedBox(height: 12),
                      _OrderSummaryCard(order: order),
                    ],
                    if (addr != null) ...[
                      const SizedBox(height: 12),
                      _DeliveryAddress(addr: addr),
                    ],
                  ],
                ),
              ),
              if (isPendingPayment)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _PayNowBottomBar(
                    total: total,
                    loading: _payingNow,
                    onPay: () => _payNow(order),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _LiveMap extends StatelessWidget {
  const _LiveMap({
    required this.tracking,
    required this.partner,
    required this.etaMinutes,
    required this.onMapCreated,
  });

  final OrderTracking tracking;
  final LatLng? partner;
  final int? etaMinutes;
  final ValueChanged<GoogleMapController> onMapCreated;

  @override
  Widget build(BuildContext context) {
    final dest = tracking.destination!;
    final origin = tracking.warehouse ?? dest;
    final polyline = tracking.polyline != null
        ? decodePolyline(tracking.polyline!)
        : const <LatLng>[];

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: SizedBox(
        height: 260,
        child: Stack(
          children: [
            GoogleMap(
              initialCameraPosition: CameraPosition(
                target: partner ?? origin,
                zoom: 14,
              ),
              onMapCreated: onMapCreated,
              markers: {
                Marker(
                  markerId: const MarkerId('dest'),
                  position: dest,
                  icon: BitmapDescriptor.defaultMarkerWithHue(
                      BitmapDescriptor.hueRed),
                  infoWindow: const InfoWindow(title: 'Drop-off'),
                ),
                if (tracking.warehouse != null)
                  Marker(
                    markerId: const MarkerId('warehouse'),
                    position: tracking.warehouse!,
                    icon: BitmapDescriptor.defaultMarkerWithHue(
                        BitmapDescriptor.hueOrange),
                    infoWindow: const InfoWindow(title: 'Dark store'),
                  ),
                if (partner != null)
                  Marker(
                    markerId: const MarkerId('rider'),
                    position: partner!,
                    icon: BitmapDescriptor.defaultMarkerWithHue(
                        BitmapDescriptor.hueYellow),
                    infoWindow: const InfoWindow(title: 'Rider'),
                  ),
              },
              polylines: polyline.length >= 2
                  ? {
                      Polyline(
                        polylineId: const PolylineId('route'),
                        points: polyline,
                        color: AppColors.primary,
                        width: 5,
                      ),
                    }
                  : const {},
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              compassEnabled: false,
            ),
            if (etaMinutes != null && tracking.status == 'out_for_delivery')
              Positioned(
                top: 12,
                right: 12,
                child: _EtaPill(minutes: etaMinutes!),
              ),
          ],
        ),
      ),
    );
  }
}

class _EtaPill extends StatelessWidget {
  const _EtaPill({required this.minutes});
  final int minutes;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(999),
        boxShadow: const [
          BoxShadow(
              color: Color(0x33000000),
              blurRadius: 8,
              offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.timer_outlined, color: AppColors.onPrimary, size: 16),
          const SizedBox(width: 4),
          Text(
            'Arriving in $minutes min',
            style: const TextStyle(
              color: AppColors.onPrimary,
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

/// Full rider card shown only while the order is out_for_delivery.
/// Once delivered we collapse to [_RateRiderCta]; once delivered + already
/// rated we just show that compact card. The full info has no place after
/// delivery completes.
class _RiderCard extends StatelessWidget {
  const _RiderCard({
    required this.rider,
    required this.etaMinutes,
    required this.onCall,
  });

  final RiderInfo rider;
  final int? etaMinutes;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    final initials = rider.name
        .split(' ')
        .where((p) => p.isNotEmpty)
        .map((p) => p[0])
        .take(2)
        .join()
        .toUpperCase();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.outline),
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: AppColors.primary,
            backgroundImage:
                (rider.photoUrl != null && rider.photoUrl!.isNotEmpty)
                    ? NetworkImage(rider.photoUrl!)
                    : null,
            child: (rider.photoUrl == null || rider.photoUrl!.isEmpty)
                ? Text(
                    initials.isEmpty ? 'QB' : initials,
                    style: const TextStyle(
                      color: AppColors.onPrimary,
                      fontWeight: FontWeight.w900,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        rider.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _RatingChip(
                      rating: rider.rating,
                      ratingCount: rider.ratingCount,
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  rider.phone,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  etaMinutes != null
                      ? 'On the way \u2022 $etaMinutes min away'
                      : 'On the way',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: onCall,
            icon: const Icon(Icons.call_outlined, size: 18),
            label: const Text('Call'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact card shown only after the order is delivered. Holds either an
/// outlined "Rate this rider" button or, once submitted, a muted "You
/// rated this rider" row. No avatar/name/phone/Call - those are only
/// useful while delivery is in progress.
class _RateRiderCta extends StatelessWidget {
  const _RateRiderCta({
    required this.feedbackSubmitted,
    required this.onRate,
  });

  final bool feedbackSubmitted;
  final VoidCallback onRate;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.outline),
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: feedbackSubmitted
          ? const Row(
              children: [
                Icon(Icons.check_circle_outline,
                    size: 18, color: AppColors.textMuted),
                SizedBox(width: 8),
                Text(
                  'You rated this rider',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                ),
              ],
            )
          : SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onRate,
                icon: const Icon(Icons.star_outline_rounded, size: 18),
                label: const Text('Rate this rider'),
              ),
            ),
    );
  }
}

class _RatingChip extends StatelessWidget {
  const _RatingChip({required this.rating, required this.ratingCount});
  final double rating;
  final int ratingCount;

  @override
  Widget build(BuildContext context) {
    final label = ratingCount == 0
        ? rating.toStringAsFixed(1)
        : '${rating.toStringAsFixed(1)} (${_shortCount(ratingCount)})';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star_rounded,
              size: 14, color: AppColors.primary),
          const SizedBox(width: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }

  /// 1234 -> 1.2k. We render rating counts in a tight chip so anything
  /// beyond ~4 chars overflows on small phones.
  String _shortCount(int n) {
    if (n < 1000) return '$n';
    final k = n / 1000;
    return '${k.toStringAsFixed(k >= 10 ? 0 : 1)}k';
  }
}

class _DeliveredBanner extends StatelessWidget {
  const _DeliveredBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline, color: AppColors.primary),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Delivered',
                    style:
                        TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                SizedBox(height: 2),
                Text(
                  'Hope you enjoy your order. Tap a product to rate it.',
                  style: TextStyle(color: AppColors.text, fontSize: 12.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard(
      {required this.number, required this.status, required this.total});
  final String number;
  final String status;
  final double total;

  @override
  Widget build(BuildContext context) {
    final accent = status == 'pending_payment'
        ? AppColors.warning
        : AppColors.primary;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.onPrimary,
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                status == 'pending_payment'
                    ? Icons.pending_actions_outlined
                    : Icons.local_shipping_outlined,
                color: accent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Order #$number',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _statusHeadline(status),
            style: const TextStyle(
                color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            _statusSub(status),
            style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('Order total',
                  style: TextStyle(color: Colors.white70, fontSize: 12)),
              const Spacer(),
              Text(
                _fmt.format(total),
                style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w900,
                    fontSize: 18),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PendingPaymentCard extends StatelessWidget {
  const _PendingPaymentCard({
    required this.total,
    required this.loading,
    required this.onPay,
  });

  final double total;
  final bool loading;
  final VoidCallback onPay;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: AppColors.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Payment pending',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                ),
                const SizedBox(height: 2),
                Text(
                  'Complete payment of ${_fmt.format(total)} to confirm your '
                  'order. We have reserved stock for you.',
                  style: const TextStyle(
                      color: AppColors.text, fontSize: 12.5, height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PayNowBottomBar extends StatelessWidget {
  const _PayNowBottomBar({
    required this.total,
    required this.loading,
    required this.onPay,
  });

  final double total;
  final bool loading;
  final VoidCallback onPay;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, MediaQuery.paddingOf(context).bottom + 12),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 18,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Amount due',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
              Text(
                _fmt.format(total),
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                ),
              ),
            ],
          ),
          const Spacer(),
          SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              onPressed: loading ? null : onPay,
              icon: loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.onPrimary,
                      ),
                    )
                  : const Icon(Icons.payments_outlined, size: 18),
              label: Text(loading ? 'Opening\u2026' : 'Pay now'),
            ),
          ),
        ],
      ),
    );
  }
}

String _statusHeadline(String s) {
  switch (s) {
    case 'pending_payment':
      return 'Payment pending';
    case 'placed':
      return 'Order placed';
    case 'confirmed':
      return 'Confirmed by vendor';
    case 'packed':
      return 'Packed and ready';
    case 'out_for_delivery':
      return 'Out for delivery';
    case 'delivered':
      return 'Delivered';
    case 'cancelled':
      return 'Cancelled';
    default:
      return s.replaceAll('_', ' ');
  }
}

String _statusSub(String s) {
  switch (s) {
    case 'pending_payment':
      return 'Complete payment to confirm this order';
    case 'placed':
      return 'We have notified the vendor';
    case 'confirmed':
      return 'Vendor is preparing your order';
    case 'packed':
      return 'Waiting for delivery partner pickup';
    case 'out_for_delivery':
      return 'Your order is on its way';
    case 'delivered':
      return 'Order delivered successfully';
    case 'cancelled':
      return 'This order has been cancelled';
    default:
      return '';
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.status});
  final String status;

  static const _baseSteps = [
    ('placed', 'Placed'),
    ('confirmed', 'Confirmed'),
    ('packed', 'Packed'),
    ('out_for_delivery', 'Out for delivery'),
    ('delivered', 'Delivered'),
  ];

  List<(String, String)> get _steps {
    // For pending-payment orders, surface the pending step at the top so
    // users immediately understand what's blocking the order.
    if (status == 'pending_payment') {
      return const [
        ('pending_payment', 'Payment pending'),
        ..._baseSteps,
      ];
    }
    return _baseSteps;
  }

  int get _currentIndex {
    final idx = _steps.indexWhere((s) => s.$1 == status);
    return idx < 0 ? 0 : idx;
  }

  @override
  Widget build(BuildContext context) {
    final steps = _steps;
    final current = _currentIndex;
    return Column(
      children: [
        for (int i = 0; i < steps.length; i++)
          _Step(
            label: steps[i].$2,
            done: i <= current,
            isLast: i == steps.length - 1,
            isActive: i == current,
            isPending: steps[i].$1 == 'pending_payment',
          ),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.label,
    required this.done,
    required this.isLast,
    required this.isActive,
    required this.isPending,
  });
  final String label;
  final bool done;
  final bool isLast;
  final bool isActive;
  final bool isPending;

  @override
  Widget build(BuildContext context) {
    final activeColor = isPending ? AppColors.warning : AppColors.primary;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: done ? activeColor : AppColors.surfaceAlt,
                  border: Border.all(
                      color: done ? AppColors.onPrimary : AppColors.outline),
                ),
                child: done
                    ? Icon(
                        isPending && isActive
                            ? Icons.priority_high
                            : Icons.check,
                        size: 14,
                        color: AppColors.onPrimary,
                      )
                    : null,
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: done ? activeColor : AppColors.outline,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 20, top: 2),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isActive ? FontWeight.w900 : FontWeight.w600,
                  color: done ? AppColors.text : AppColors.textMuted,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShipmentTile extends StatelessWidget {
  const _ShipmentTile({required this.shipment});
  final Map<String, dynamic> shipment;

  @override
  Widget build(BuildContext context) {
    // Try a few plausible shapes depending on whether the query joined the
    // vendors table / aggregated order items.
    final vendor = (shipment['vendor_name'] as String?) ??
        ((shipment['vendors'] as Map?)?['name'] as String?) ??
        'Vendor';
    final itemsList = (shipment['order_items'] as List?);
    final items = (shipment['item_count'] as num?)?.toInt() ??
        itemsList?.length ??
        0;
    final status = shipment['status'] as String? ?? 'pending';
    final mode = shipment['delivery_mode'] as String? ?? 'standard';
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.outline),
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(AppRadii.sm),
            ),
            child: const Icon(Icons.inventory_2_outlined),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(vendor,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                Text('$items items \u2022 $mode',
                    style: const TextStyle(
                        color: AppColors.textMuted, fontSize: 12.5)),
              ],
            ),
          ),
          Text(
            status.replaceAll('_', ' ').toUpperCase(),
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _DeliveryAddress extends StatelessWidget {
  const _DeliveryAddress({required this.addr});
  final Map<String, dynamic> addr;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.location_on_outlined),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(addr['label'] as String? ?? 'Delivery address',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(
                  '${addr['line1'] ?? ''}, ${addr['city'] ?? ''} ${addr['pincode'] ?? ''}',
                  style: const TextStyle(color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Flat list of every order_item across all shipments. Each row reads
/// like a printed receipt: product name, qty x unit price as subtitle,
/// line total right-aligned.
class _OrderItemsList extends StatelessWidget {
  const _OrderItemsList({required this.shipments});
  final List<dynamic> shipments;

  static final _money = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '\u20B9',
    decimalDigits: 0,
  );

  @override
  Widget build(BuildContext context) {
    final items = <Map<String, dynamic>>[];
    for (final raw in shipments) {
      final ship = (raw as Map).cast<String, dynamic>();
      final list = (ship['order_items'] as List?) ?? const <dynamic>[];
      for (final it in list) {
        items.add((it as Map).cast<String, dynamic>());
      }
    }
    if (items.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.outline),
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Items',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          for (int i = 0; i < items.length; i++) ...[
            _buildRow(items[i]),
            if (i != items.length - 1)
              const Divider(height: 16, color: AppColors.outline),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildRow(Map<String, dynamic> item) {
    final name = (item['name'] as String?) ?? 'Product';
    final qty = (item['quantity'] as num?)?.toInt() ?? 1;
    final unit = (item['unit_price'] as num?)?.toDouble() ?? 0;
    final lineTotal = (item['line_total'] as num?)?.toDouble() ?? unit * qty;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
              ),
              const SizedBox(height: 2),
              Text(
                '$qty \u00d7 ${_money.format(unit)}',
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(
          _money.format(lineTotal),
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
        ),
      ],
    );
  }
}

/// Bill summary card. Shows the payment method banner up top and a
/// receipt-style table below: subtotal -> discount (if applied) -> tax
/// -> shipping -> grand total.
class _OrderSummaryCard extends StatelessWidget {
  const _OrderSummaryCard({required this.order});
  final Map<String, dynamic> order;

  static final _money = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '\u20B9',
    decimalDigits: 0,
  );

  String _paymentLabel() {
    final method = (order['payment_method'] as String?) ?? '';
    final status = (order['payment_status'] as String?) ?? '';
    final pretty = switch (method.toLowerCase()) {
      'upi' => 'UPI',
      'card' => 'Card',
      'netbanking' => 'Net banking',
      'wallet' => 'Wallet',
      'credit' => 'Credit line',
      'cod' => 'Cash on delivery',
      _ => method.isEmpty ? 'Online' : method,
    };
    if (method == 'cod') return 'Cash on delivery';
    if (status == 'captured') return 'Paid via $pretty';
    if (status == 'failed') return 'Payment failed - $pretty';
    return pretty;
  }

  @override
  Widget build(BuildContext context) {
    final subtotal = (order['subtotal'] as num?)?.toDouble() ?? 0;
    final discount = (order['discount_total'] as num?)?.toDouble() ?? 0;
    final tax = (order['tax_total'] as num?)?.toDouble() ?? 0;
    final shipping = (order['shipping_total'] as num?)?.toDouble() ?? 0;
    final total = (order['grand_total'] as num?)?.toDouble() ?? 0;
    final coupon = (order['coupon_code'] as String?)?.trim();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.outline),
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_balance_wallet_outlined,
                  size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _paymentLabel(),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 18, color: AppColors.outline),
          _row('Subtotal', _money.format(subtotal)),
          if (discount > 0)
            _row(
              coupon != null && coupon.isNotEmpty
                  ? 'Discount ($coupon)'
                  : 'Discount',
              '\u2212 ${_money.format(discount)}',
              valueColor: AppColors.primary,
            ),
          if (tax > 0) _row('Tax', _money.format(tax)),
          _row(
            'Shipping',
            shipping > 0 ? _money.format(shipping) : 'Free',
          ),
          const Divider(height: 16, color: AppColors.outline),
          Row(
            children: [
              const Text(
                'Total',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
              ),
              const Spacer(),
              Text(
                _money.format(total),
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 13,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: valueColor ?? AppColors.text,
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact CTA shown only when the order is delivered. Reads the same
/// myOrderReviewsProvider used by the rating sheet, so it knows whether
/// the user has rated everything (-> "You rated this order") or has
/// pending products (-> outlined "Rate the products" button).
class _RateOrderCta extends ConsumerWidget {
  const _RateOrderCta({required this.orderId, required this.items});

  final String orderId;
  final List<OrderItemForRating> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviewsAsync = ref.watch(myOrderReviewsProvider(orderId));
    final ratedIds = reviewsAsync.maybeWhen(
      data: (rows) => rows
          .map((r) => r['product_id'] as String?)
          .whereType<String>()
          .toSet(),
      orElse: () => <String>{},
    );
    final allRated =
        items.isNotEmpty && items.every((i) => ratedIds.contains(i.productId));

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.outline),
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: allRated
          ? const Row(
              children: [
                Icon(Icons.check_circle_outline,
                    size: 18, color: AppColors.textMuted),
                SizedBox(width: 8),
                Text(
                  'You rated this order',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                ),
              ],
            )
          : SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: items.isEmpty
                    ? null
                    : () async {
                        await OrderRatingSheet.show(
                          context,
                          orderId: orderId,
                          items: items,
                        );
                        // Reload the rated set after the sheet closes so
                        // the CTA flips to the "all rated" state when the
                        // user covered everything.
                        ref.invalidate(myOrderReviewsProvider(orderId));
                      },
                icon: const Icon(Icons.reviews_outlined, size: 18),
                label: const Text('Rate the products'),
              ),
            ),
    );
  }
}
