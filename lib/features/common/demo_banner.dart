import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_state.dart';
import '../../core/config.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';

/// Thin strip reminding people they're in the sample shop, with a way out.
class DemoBanner extends ConsumerWidget {
  const DemoBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider).value;
    if (session == null || !session.isDemo) return const SizedBox.shrink();
    final switchTo = session.isShopkeeper ? false : true;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      decoration: BoxDecoration(
        color: Brand.saffron.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Brand.saffron.withValues(alpha: 0.5)),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.science_outlined, color: Brand.saffron, size: 20),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    context.tr('Demo shop · not saved', 'डेमो दुकान · सेव नहीं होता'),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: TextButton(
                  onPressed: () {
                    ref.read(sessionProvider.notifier).startDemo(asShopkeeper: switchTo);
                    context.go(switchTo ? '/owner' : '/shop');
                  },
                  child: Text(
                    switchTo
                        ? context.tr('Shopkeeper view', 'दुकानदार व्यू')
                        : context.tr('Customer view', 'ग्राहक व्यू'),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              if (AppConfig.hasBackend)
                IconButton(
                  tooltip: context.tr('Exit demo', 'डेमो बंद करें'),
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () async {
                    await ref.read(sessionProvider.notifier).exitDemo();
                    if (context.mounted) context.go('/shop');
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}
