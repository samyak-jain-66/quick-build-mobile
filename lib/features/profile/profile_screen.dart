import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_controller.dart';
import '../../theme/app_theme.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(currentSessionProvider);
    final email = session?.user.email;
    final phone = session?.user.phone;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () async {
              await ref.read(authControllerProvider.notifier).signOut();
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Header(
            name: phone ?? email ?? 'Guest',
            email: email ?? '',
          ),
          const SizedBox(height: 20),
          _Section(
            title: 'My account',
            children: [
              _Tile(
                icon: Icons.receipt_long_outlined,
                title: 'My orders',
                onTap: () => context.push('/orders'),
              ),
              _Tile(
                icon: Icons.favorite_outline,
                title: 'My wishlist',
                onTap: () => context.push('/wishlist'),
              ),
              _Tile(
                icon: Icons.location_on_outlined,
                title: 'Addresses',
                onTap: () => context.push('/addresses'),
              ),
              _Tile(
                icon: Icons.account_balance_wallet_outlined,
                title: 'Wallet',
                onTap: () => context.push('/wallet'),
              ),
              _Tile(
                icon: Icons.request_quote_outlined,
                title: 'Bulk quotes (RFQ)',
                onTap: () => context.push('/rfqs'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _Section(
            title: 'Business',
            children: const [
              _Tile(
                icon: Icons.receipt_outlined,
                title: 'GST details',
                subtitle: 'Manage your GSTIN and invoices',
              ),
              _Tile(
                icon: Icons.credit_card_outlined,
                title: 'Credit line',
                subtitle: 'Pay-later and credit eligibility',
              ),
            ],
          ),
          const SizedBox(height: 16),
          _Section(
            title: 'Help',
            children: const [
              _Tile(
                icon: Icons.help_outline,
                title: 'Help & support',
              ),
              _Tile(
                icon: Icons.info_outline,
                title: 'About Quick-Build',
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Text(
            'v0.1.0',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.name, required this.email});
  final String name;
  final String email;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.onPrimary,
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: AppColors.primary,
            child: Text(
              (name.isNotEmpty ? name[0] : 'Q').toUpperCase(),
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: AppColors.onPrimary,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    )),
                if (email.isNotEmpty)
                  Text(email,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 6),
          child: Text(title,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textMuted)),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.outline),
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title,
          style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: subtitle != null ? Text(subtitle!) : null,
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
