import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/app_state.dart';
import 'core/config.dart';
import 'core/i18n.dart';
import 'core/router.dart';
import 'core/theme.dart';
import 'core/widgets/common.dart';

class KiranaApp extends ConsumerWidget {
  const KiranaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(prefsProvider);
    final router = ref.watch(routerProvider);
    final brand = parseHexColor(ref.watch(catalogProvider.select((c) => c.value?.shop.brandColor)));
    return MaterialApp.router(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light, brand: brand),
      darkTheme: buildTheme(Brightness.dark, brand: brand),
      themeMode: prefs.themeMode,
      routerConfig: router,
      builder: (context, child) {
        // Respect large system fonts, but stop at a size the layouts can hold.
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(textScaler: mq.textScaler.clamp(minScaleFactor: 1, maxScaleFactor: 1.8)),
          child: LangScope(language: prefs.language, child: child ?? const SizedBox()),
        );
      },
    );
  }
}
