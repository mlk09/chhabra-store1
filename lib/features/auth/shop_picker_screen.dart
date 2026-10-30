import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_state.dart';
import '../../core/config.dart';
import '../../core/i18n.dart';
import '../../core/router.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/product_widgets.dart';
import '../../data/models/shop.dart';
import '../../domain/search.dart';
import 'welcome_screen.dart';

final _shopListProvider = FutureProvider.autoDispose<List<ShopSummary>>((ref) async {
  final s = await ref.watch(sessionProvider.future);
  return s.backend.listShops();
});

/// Platform app start: find your shop by name / city / code.
/// Shop links (…/app/?shop=code) and QR posters skip this screen.
class ShopPickerScreen extends ConsumerStatefulWidget {
  const ShopPickerScreen({super.key});
  @override
  ConsumerState<ShopPickerScreen> createState() => _ShopPickerScreenState();
}

class _ShopPickerScreenState extends ConsumerState<ShopPickerScreen> {
  final _q = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _open(String slug) async {
    setState(() => _busy = true);
    try {
      final ok = await ref.read(sessionProvider.notifier).selectShop(slug);
      if (!mounted) return;
      if (!ok) {
        showSnack(
          context,
          context.tr('No shop with this code. Check the spelling.', 'इस कोड की कोई दुकान नहीं। स्पेलिंग जाँचें।'),
          error: true,
        );
        return;
      }
      context.go(homeFor(ref.read(sessionProvider).requireValue, ref.read(prefsProvider)));
    } catch (e) {
      if (mounted) showSnack(context, errorText(context, e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final prefs = ref.watch(prefsProvider);
    final shops = ref.watch(_shopListProvider);
    final q = normalizeSearch(_q.text);
    final list = (shops.value ?? const <ShopSummary>[])
        .where((s) => q.isEmpty || normalizeSearch('${s.name} ${s.nameHi ?? ''} ${s.city ?? ''} ${s.slug}').contains(q))
        .toList();

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Row(
                  children: [
                    const AppLogo(size: 52),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        context.pick(AppConfig.appName, AppConfig.appNameHi),
                        style: t.textTheme.headlineSmall,
                      ),
                    ),
                    SegmentedButton<AppLanguage>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: AppLanguage.en, label: Text('EN')),
                        ButtonSegment(value: AppLanguage.hi, label: Text('हिं')),
                      ],
                      selected: {prefs.language},
                      onSelectionChanged: (s) => ref.read(prefsProvider.notifier).setLanguage(s.first),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(context.tr('Find your shop', 'अपनी दुकान ढूँढें'), style: t.textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  context.tr(
                    'Search by name or city, or type the shop code from its QR poster.',
                    'नाम या शहर से खोजें, या QR पोस्टर पर लिखा दुकान कोड डालें।',
                  ),
                  style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _q,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (v) => v.trim().isEmpty ? null : _open(v.trim().toLowerCase().replaceAll(' ', '-')),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: context.tr('Shop name, city or code', 'दुकान का नाम, शहर या कोड'),
                  ),
                ),
                const SizedBox(height: 8),
                if (shops.isLoading) const Padding(padding: EdgeInsets.all(24), child: LoadingView()),
                if (shops.hasError) ErrorView(error: shops.error!, onRetry: () => ref.invalidate(_shopListProvider)),
                for (final s in list.take(50))
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: ShopLogo(name: s.name, logoPath: s.logoPath, brandColor: s.brandColor, size: 44),
                      title: Text(context.pick(s.name, s.nameHi)),
                      subtitle: Text([s.city, s.slug].whereType<String>().join(' · ')),
                      trailing: const Icon(Icons.chevron_right),
                      enabled: !_busy,
                      onTap: () => _open(s.slug),
                    ),
                  ),
                if (shops.hasValue && list.isEmpty && _q.text.trim().isNotEmpty)
                  OutlinedButton(
                    onPressed: _busy ? null : () => _open(_q.text.trim().toLowerCase().replaceAll(' ', '-')),
                    child: Text(
                      context.tr('Open shop code "${_q.text.trim()}"', 'दुकान कोड "${_q.text.trim()}" खोलें'),
                    ),
                  ),
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.storefront_rounded),
                  label: Text(context.tr('I am a shopkeeper — Log in', 'मैं दुकानदार हूँ — लॉग इन')),
                  onPressed: () => context.push('/login'),
                ),
                const SizedBox(height: 20),
                Text(context.tr('Or try the demo shop:', 'या डेमो दुकान देखें:'), textAlign: TextAlign.center),
                const SizedBox(height: 10),
                const DemoButtons(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
