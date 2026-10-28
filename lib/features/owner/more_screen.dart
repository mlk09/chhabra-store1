import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_state.dart';
import '../../core/i18n.dart';
import '../../core/widgets/common.dart';
import '../../data/models/member.dart';
import '../common/demo_banner.dart';

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sessionProvider).value;
    final shop = ref.watch(catalogProvider).value?.shop;
    final t = Theme.of(context);
    if (s == null) return const Scaffold(body: LoadingView());
    final role = s.membership.role == ShopRole.owner ? context.tr('Owner', 'मालिक') : context.tr('Staff', 'स्टाफ़');
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('More', 'और'))),
      body: ListView(
        children: [
          const DemoBanner(),
          ListTile(
            leading: const AppLogo(size: 48),
            title: Text(shop == null ? '' : context.pick(shop.name, shop.nameHi), style: t.textTheme.titleMedium),
            subtitle: Text('${s.user?.email ?? ''} · $role'),
          ),
          const Divider(),
          _Tile(Icons.category_outlined, context.tr('Categories', 'कैटेगरी'), () => context.push('/owner/categories')),
          _Tile(
            Icons.add_photo_alternate_outlined,
            context.tr('Bulk photos (AI)', 'एक साथ फ़ोटो (AI)'),
            () => context.push('/owner/bulk-photos'),
          ),
          if (s.can(Perm.prices))
            _Tile(
              Icons.percent_rounded,
              context.tr('Bulk price update', 'एक साथ रेट बदलें'),
              () => context.push('/owner/bulk-price'),
            ),
          if (s.can(Perm.settings))
            _Tile(
              Icons.store_mall_directory_outlined,
              context.tr('Shop details, UPI & delivery', 'दुकान, UPI और डिलीवरी'),
              () => context.push('/owner/shop'),
            ),
          _Tile(
            Icons.visibility_outlined,
            context.tr('See shop as customer', 'ग्राहक की नज़र से देखें'),
            () => context.go('/shop'),
          ),
          _Tile(
            Icons.settings_outlined,
            context.tr('Language, theme & account', 'भाषा, थीम और खाता'),
            () => context.push('/settings'),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout_rounded),
            title: Text(s.isDemo ? context.tr('Exit demo', 'डेमो बंद करें') : context.tr('Log out', 'लॉग आउट')),
            onTap: () async {
              await ref.read(sessionProvider.notifier).signOut();
              if (context.mounted) context.go('/shop');
            },
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile(this.icon, this.title, this.onTap);
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) =>
      ListTile(leading: Icon(icon), title: Text(title), trailing: const Icon(Icons.chevron_right), onTap: onTap);
}
