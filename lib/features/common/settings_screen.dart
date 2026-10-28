import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_state.dart';
import '../../core/i18n.dart';
import '../../core/widgets/common.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(prefsProvider);
    final session = ref.watch(sessionProvider).value;
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Settings', 'सेटिंग्स'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(context.tr('Language', 'भाषा'), style: t.textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<AppLanguage>(
            segments: const [
              ButtonSegment(value: AppLanguage.en, label: Text('English')),
              ButtonSegment(value: AppLanguage.hi, label: Text('हिंदी')),
            ],
            selected: {prefs.language},
            onSelectionChanged: (v) => ref.read(prefsProvider.notifier).setLanguage(v.first),
          ),
          const SizedBox(height: 24),
          Text(context.tr('Theme', 'थीम'), style: t.textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<ThemeMode>(
            segments: [
              ButtonSegment(
                value: ThemeMode.dark,
                icon: const Icon(Icons.dark_mode_outlined),
                label: Text(context.tr('Dark', 'डार्क')),
              ),
              ButtonSegment(
                value: ThemeMode.light,
                icon: const Icon(Icons.light_mode_outlined),
                label: Text(context.tr('Light', 'लाइट')),
              ),
              ButtonSegment(
                value: ThemeMode.system,
                icon: const Icon(Icons.phone_android),
                label: Text(context.tr('Phone', 'फ़ोन')),
              ),
            ],
            selected: {prefs.themeMode},
            onSelectionChanged: (v) => ref.read(prefsProvider.notifier).setTheme(v.first),
          ),
          const SizedBox(height: 12),
          Text(
            context.tr(
              'Text size follows your phone\'s font size setting.',
              'अक्षरों का साइज़ फ़ोन की फ़ॉन्ट सेटिंग से चलता है।',
            ),
            style: t.textTheme.bodySmall,
          ),
          if (session != null && session.isLoggedIn && !session.isDemo) ...[
            const SizedBox(height: 32),
            Text(context.tr('Account', 'खाता'), style: t.textTheme.titleMedium),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: Icon(Icons.delete_forever_outlined, color: t.colorScheme.error),
                title: Text(
                  context.tr('Delete my account', 'मेरा खाता हटाएँ'),
                  style: TextStyle(color: t.colorScheme.error),
                ),
                subtitle: Text(
                  context.tr(
                    'Removes your login, profile and saved addresses.',
                    'आपका लॉगिन, प्रोफ़ाइल और पते हट जाएँगे।',
                  ),
                ),
                onTap: () => _confirmDelete(context, ref),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('Delete account?', 'खाता हटाएँ?')),
        content: Text(
          ctx.tr(
            'This cannot be undone. Bills kept by the shop for tax records are not deleted.',
            'यह वापस नहीं होगा। टैक्स रिकॉर्ड के लिए दुकान के बिल नहीं हटते।',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('Cancel', 'रद्द करें'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.tr('Delete', 'हटाएँ')),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await ref.read(backendProvider).deleteAccount();
      await ref.read(sessionProvider.notifier).signOut();
      if (!context.mounted) return;
      showSnack(context, context.tr('Your account was deleted.', 'आपका खाता हटा दिया गया।'));
      context.go('/shop');
    } catch (e) {
      if (context.mounted) showSnack(context, errorText(context, e), error: true);
    }
  }
}
