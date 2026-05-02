import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_client.dart';
import '../../theme/app_theme.dart';

final _fmt = NumberFormat.currency(
  locale: 'en_IN',
  symbol: '\u20B9',
  decimalDigits: 0,
);
final _date = DateFormat('dd MMM, hh:mm a');

class WalletRepository {
  WalletRepository(this._dio);
  final Dio _dio;

  Future<Map<String, dynamic>> summary() async {
    final res = await _dio.get<Map<String, dynamic>>('/wallet');
    return res.data ?? {};
  }

  Future<List<Map<String, dynamic>>> transactions() async {
    final res = await _dio.get<List<dynamic>>('/wallet/transactions');
    return (res.data ?? const [])
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }
}

final walletRepositoryProvider = Provider<WalletRepository>(
  (ref) => WalletRepository(ref.watch(apiClientProvider)),
);

final walletSummaryProvider = FutureProvider<Map<String, dynamic>>(
  (ref) => ref.watch(walletRepositoryProvider).summary(),
);

final walletTransactionsProvider =
    FutureProvider<List<Map<String, dynamic>>>(
  (ref) => ref.watch(walletRepositoryProvider).transactions(),
);

class WalletScreen extends ConsumerWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(walletSummaryProvider);
    final txns = ref.watch(walletTransactionsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Wallet')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(walletSummaryProvider);
          ref.invalidate(walletTransactionsProvider);
          await Future.wait<void>([
            ref.read(walletSummaryProvider.future),
            ref.read(walletTransactionsProvider.future),
          ]);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _BalanceCard(summary: summary),
            const SizedBox(height: 20),
            const Text('Recent activity',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            txns.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (e, _) => Text('Error: $e'),
              data: (list) {
                if (list.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 30),
                    child: Column(
                      children: const [
                        Icon(Icons.history,
                            size: 48, color: AppColors.textMuted),
                        SizedBox(height: 8),
                        Text('No wallet activity yet',
                            style: TextStyle(color: AppColors.textMuted)),
                      ],
                    ),
                  );
                }
                return Column(
                  children: [
                    for (final t in list) _TxnTile(txn: t),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.summary});
  final AsyncValue<Map<String, dynamic>> summary;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.onPrimary,
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_balance_wallet,
                  color: AppColors.primary),
              const SizedBox(width: 8),
              const Text('Wallet balance',
                  style: TextStyle(color: Colors.white70)),
            ],
          ),
          const SizedBox(height: 10),
          summary.when(
            loading: () => const Text(
              '—',
              style: TextStyle(
                color: AppColors.primary,
                fontSize: 34,
                fontWeight: FontWeight.w900,
              ),
            ),
            error: (e, _) => Text('$e',
                style: const TextStyle(color: Colors.white70)),
            data: (s) {
              final bal = (s['balance'] as num?)?.toDouble() ?? 0;
              return Text(
                _fmt.format(bal),
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                ),
              );
            },
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.4)),
                  ),
                  onPressed: () {},
                  icon: const Icon(Icons.add),
                  label: const Text('Add money'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.receipt_outlined),
                  label: const Text('Statements'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TxnTile extends StatelessWidget {
  const _TxnTile({required this.txn});
  final Map<String, dynamic> txn;

  @override
  Widget build(BuildContext context) {
    final amount = (txn['amount'] as num?)?.toDouble() ?? 0;
    final type = txn['type'] as String? ?? 'debit';
    final credit = type == 'credit';
    final desc = txn['description'] as String? ?? type.toUpperCase();
    final createdRaw = txn['created_at'] as String?;
    DateTime? created;
    if (createdRaw != null) created = DateTime.tryParse(createdRaw);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.divider),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(AppRadii.sm),
            ),
            child: Icon(
              credit ? Icons.south_west : Icons.north_east,
              color: credit ? AppColors.success : AppColors.danger,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(desc,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(
                  created != null ? _date.format(created) : '',
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          Text(
            '${credit ? '+' : '-'}${_fmt.format(amount)}',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: credit ? AppColors.success : AppColors.danger,
            ),
          ),
        ],
      ),
    );
  }
}
