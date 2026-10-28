import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_state.dart';
import '../../core/config.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';

class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final prefs = ref.watch(prefsProvider);
    void done(String to) {
      ref.read(prefsProvider.notifier).markWelcomeSeen();
      context.go(to);
    }

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: ListView(
              padding: const EdgeInsets.all(24),
              shrinkWrap: true,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: SegmentedButton<AppLanguage>(
                    segments: const [
                      ButtonSegment(value: AppLanguage.en, label: Text('English')),
                      ButtonSegment(value: AppLanguage.hi, label: Text('हिंदी')),
                    ],
                    selected: {prefs.language},
                    onSelectionChanged: (s) => ref.read(prefsProvider.notifier).setLanguage(s.first),
                  ),
                ),
                const SizedBox(height: 24),
                const Center(child: AppLogo(size: 96)),
                const SizedBox(height: 20),
                Text(
                  context.pick(AppConfig.appName, AppConfig.appNameHi),
                  textAlign: TextAlign.center,
                  style: t.textTheme.headlineSmall,
                ),
                const SizedBox(height: 6),
                Text(
                  context.tr(
                    'Railway Road, Karnal · Home delivery within 3 km',
                    'रेलवे रोड, करनाल · 3 किमी तक होम डिलीवरी',
                  ),
                  textAlign: TextAlign.center,
                  style: t.textTheme.bodyLarge?.copyWith(color: t.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 36),
                if (AppConfig.hasBackend) ...[
                  FilledButton.icon(
                    icon: const Icon(Icons.shopping_basket_rounded),
                    label: Text(context.tr('Start shopping', 'खरीदारी शुरू करें')),
                    onPressed: () => done('/shop'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.login_rounded),
                    label: Text(context.tr('Log in / Sign up', 'लॉग इन / साइन अप')),
                    onPressed: () {
                      ref.read(prefsProvider.notifier).markWelcomeSeen();
                      context.push('/login');
                    },
                  ),
                  const SizedBox(height: 28),
                  Row(
                    children: [
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          context.tr('or try without an account', 'या बिना खाते के देखें'),
                          style: t.textTheme.bodySmall,
                        ),
                      ),
                      const Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 16),
                ] else
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Text(
                        context.tr(
                          'This build runs in Demo mode only (no shop server connected yet).',
                          'यह बिल्ड सिर्फ़ डेमो मोड में है (अभी दुकान का सर्वर जुड़ा नहीं है)।',
                        ),
                        style: t.textTheme.bodyMedium,
                      ),
                    ),
                  ),
                if (!AppConfig.hasBackend) const SizedBox(height: 16),
                _DemoButtons(onPicked: () => ref.read(prefsProvider.notifier).markWelcomeSeen()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Try as customer / shopkeeper" — sample shop, no sign-up, no internet.
class _DemoButtons extends ConsumerWidget {
  const _DemoButtons({this.onPicked});
  final VoidCallback? onPicked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void start(bool shopkeeper) {
      onPicked?.call();
      ref.read(sessionProvider.notifier).startDemo(asShopkeeper: shopkeeper);
      context.go(shopkeeper ? '/owner' : '/shop');
    }

    return Row(
      children: [
        Expanded(
          child: _DemoTile(
            icon: Icons.person_rounded,
            color: Brand.green,
            title: context.tr('Demo: Customer', 'डेमो: ग्राहक'),
            onTap: () => start(false),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _DemoTile(
            icon: Icons.storefront_rounded,
            color: Brand.saffron,
            title: context.tr('Demo: Shopkeeper', 'डेमो: दुकानदार'),
            onTap: () => start(true),
          ),
        ),
      ],
    );
  }
}

class _DemoTile extends StatelessWidget {
  const _DemoTile({required this.icon, required this.color, required this.title, required this.onTap});
  final IconData icon;
  final Color color;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleSmall),
          ],
        ),
      ),
    ),
  );
}

/// Re-usable demo entry for other screens (account, login).
class DemoButtons extends StatelessWidget {
  const DemoButtons({super.key});
  @override
  Widget build(BuildContext context) => const _DemoButtons();
}
