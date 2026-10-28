import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_state.dart';
import '../../core/config.dart';
import '../../core/i18n.dart';
import '../../core/widgets/common.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppLogo(size: 88),
            const SizedBox(height: 20),
            Text(context.pick(AppConfig.appName, AppConfig.appNameHi), style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 28),
            const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
          ],
        ),
      ),
    );
  }
}

/// Shown instead of a blank screen when startup fails (no internet, server down…).
class StartupErrorScreen extends ConsumerWidget {
  const StartupErrorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boot = ref.watch(bootstrapProvider);
    final session = ref.watch(sessionProvider);
    final error = boot.error ?? session.error ?? 'Unknown error';
    return Scaffold(
      body: SafeArea(
        child: MessageView(
          icon: Icons.wifi_off_rounded,
          title: context.tr('Could not open the shop', 'दुकान नहीं खुल पाई'),
          message:
              '${errorText(context, error)}\n\n${context.tr('Check your internet and try again.', 'इंटरनेट चेक करें और फिर से कोशिश करें।')}',
          actionLabel: context.tr('Try again', 'फिर से कोशिश करें'),
          onAction: () {
            ref.invalidate(bootstrapProvider);
            ref.invalidate(sessionProvider);
          },
        ),
      ),
      bottomNavigationBar: boot.hasValue
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.play_circle_outline),
                  label: Text(context.tr('Try the demo instead', 'इसके बजाय डेमो देखें')),
                  onPressed: () => ref.read(sessionProvider.notifier).startDemo(asShopkeeper: false),
                ),
              ),
            )
          : null,
    );
  }
}
