import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_client.dart';
import '../../theme/app_theme.dart';

final _date = DateFormat('dd MMM, yyyy');

class RfqRepository {
  RfqRepository(this._dio);
  final Dio _dio;

  Future<List<Map<String, dynamic>>> list() async {
    final res = await _dio.get<List<dynamic>>('/rfqs');
    return (res.data ?? const [])
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<void> create(Map<String, dynamic> payload) async {
    await _dio.post<void>('/rfqs', data: payload);
  }
}

final rfqRepositoryProvider = Provider<RfqRepository>(
  (ref) => RfqRepository(ref.watch(apiClientProvider)),
);

final rfqsProvider = FutureProvider<List<Map<String, dynamic>>>(
  (ref) => ref.watch(rfqRepositoryProvider).list(),
);

class RfqListScreen extends ConsumerWidget {
  const RfqListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rfqs = ref.watch(rfqsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Bulk quotes')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('New quote'),
      ),
      body: rfqs.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) {
          if (list.isEmpty) {
            return const _EmptyState();
          }
          return RefreshIndicator(
            onRefresh: () => ref.refresh(rfqsProvider.future),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final r = list[i];
                final title = r['title'] as String? ?? 'Request';
                final category = r['category_name'] as String? ?? '';
                final qty = (r['quantity'] as num?)?.toInt() ?? 0;
                final unit = r['unit'] as String? ?? '';
                final status = r['status'] as String? ?? 'open';
                final quotes = (r['quote_count'] as num?)?.toInt() ?? 0;
                final createdRaw = r['created_at'] as String?;
                DateTime? created;
                if (createdRaw != null) {
                  created = DateTime.tryParse(createdRaw);
                }
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
                          Expanded(
                            child: Text(title,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 15)),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: status == 'open'
                                  ? AppColors.primary
                                  : AppColors.surfaceAlt,
                              borderRadius:
                                  BorderRadius.circular(AppRadii.pill),
                            ),
                            child: Text(
                              status.toUpperCase(),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                color: status == 'open'
                                    ? AppColors.onPrimary
                                    : AppColors.text,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '$category \u2022 $qty $unit',
                        style: const TextStyle(color: AppColors.textMuted),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Icon(Icons.forum_outlined,
                              size: 16, color: AppColors.textMuted),
                          const SizedBox(width: 4),
                          Text('$quotes quotes received',
                              style: const TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 12.5)),
                          const Spacer(),
                          Text(
                            created != null ? _date.format(created) : '',
                            style: const TextStyle(
                                color: AppColors.textMuted, fontSize: 12.5),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  void _openForm(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _RfqForm(onSaved: () => ref.invalidate(rfqsProvider)),
    );
  }
}

class _RfqForm extends ConsumerStatefulWidget {
  const _RfqForm({required this.onSaved});
  final VoidCallback onSaved;

  @override
  ConsumerState<_RfqForm> createState() => _RfqFormState();
}

class _RfqFormState extends ConsumerState<_RfqForm> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _qty = TextEditingController();
  final _unit = TextEditingController(text: 'kg');
  final _pincode = TextEditingController();
  DateTime? _needBy;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_title, _description, _qty, _unit, _pincode]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final qty = int.tryParse(_qty.text.trim());
    if (_title.text.trim().isEmpty || qty == null || qty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fill title and valid quantity')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(rfqRepositoryProvider).create({
        'title': _title.text.trim(),
        'description': _description.text.trim(),
        'quantity': qty,
        'unit': _unit.text.trim(),
        'delivery_pincode': _pincode.text.trim(),
        if (_needBy != null)
          'need_by': _needBy!.toIso8601String().substring(0, 10),
      });
      if (!mounted) return;
      widget.onSaved();
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e')),
      );
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        8,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Request a bulk quote',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            const SizedBox(height: 12),
            TextField(
              controller: _title,
              decoration: const InputDecoration(
                  hintText: 'Title (e.g. OPC Cement - 50t)*'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _description,
              maxLines: 3,
              decoration: const InputDecoration(
                  hintText: 'Describe the requirement'),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _qty,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(hintText: 'Quantity*'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _unit,
                  decoration:
                      const InputDecoration(hintText: 'Unit (kg/ton/bag)'),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            TextField(
              controller: _pincode,
              keyboardType: TextInputType.number,
              decoration:
                  const InputDecoration(hintText: 'Delivery pincode'),
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                  initialDate: DateTime.now().add(const Duration(days: 7)),
                );
                if (picked != null) setState(() => _needBy = picked);
              },
              child: InputDecorator(
                decoration: const InputDecoration(hintText: 'Need by'),
                child: Text(
                  _needBy != null ? _date.format(_needBy!) : 'Pick a date',
                  style: TextStyle(
                    color: _needBy != null
                        ? AppColors.text
                        : AppColors.textMuted,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.onPrimary),
                    )
                  : const Text('Submit request'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.request_quote_outlined,
                size: 64, color: AppColors.textMuted),
            SizedBox(height: 12),
            Text('No quote requests yet',
                style:
                    TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            SizedBox(height: 6),
            Text(
              'Need large volumes? Request a quote and vendors will respond.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
