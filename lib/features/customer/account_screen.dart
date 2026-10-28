import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_state.dart';
import '../../core/config.dart';
import '../../core/i18n.dart';
import '../../core/widgets/common.dart';
import '../auth/welcome_screen.dart';
import '../common/demo_banner.dart';

class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sessionProvider).value;
    final t = Theme.of(context);
    if (s == null) return const Scaffold(body: LoadingView());
    final user = s.user;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Account', 'खाता'))),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          const DemoBanner(),
          if (s.isLoggedIn && !s.isDemo)
            ListTile(
              leading: CircleAvatar(
                radius: 26,
                child: Text(
                  (user!.name ?? user.email ?? '?').characters.first.toUpperCase(),
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                ),
              ),
              title: Text(user.name ?? context.tr('Customer', 'ग्राहक'), style: t.textTheme.titleMedium),
              subtitle: Text(user.email ?? ''),
            )
          else if (!s.isDemo && AppConfig.hasBackend)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    context.tr(
                      'Log in to place orders and track them.',
                      'ऑर्डर देने और ट्रैक करने के लिए लॉग इन करें।',
                    ),
                    style: t.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: () => context.push('/login'), child: Text(context.tr('Log in', 'लॉग इन'))),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: () => context.push('/signup'),
                    child: Text(context.tr('Create account', 'खाता बनाएँ')),
                  ),
                ],
              ),
            ),
          if (s.isShopkeeper)
            ListTile(
              leading: const Icon(Icons.storefront_rounded),
              title: Text(context.tr('Shop management', 'दुकान मैनेजमेंट')),
              onTap: () => context.go('/owner'),
            ),
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: Text(context.tr('Language, theme & account', 'भाषा, थीम और खाता')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings'),
          ),
          if (!s.isDemo) ...[
            const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(context.tr('Try the demo shop', 'डेमो दुकान आज़माएँ'), style: t.textTheme.titleMedium),
            ),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: DemoButtons()),
          ],
          if (s.isLoggedIn && !s.isDemo) ...[
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.logout_rounded),
              title: Text(context.tr('Log out', 'लॉग आउट')),
              onTap: () async {
                await ref.read(sessionProvider.notifier).signOut();
                if (context.mounted) context.go('/shop');
              },
            ),
          ],
        ],
      ),
    );
  }
}
