import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthChangeEvent, Supabase;

import '../features/auth/auth_screens.dart';
import '../features/auth/welcome_screen.dart';
import '../features/common/settings_screen.dart';
import '../features/customer/account_screen.dart';
import '../features/customer/category_screen.dart';
import '../features/customer/customer_home.dart';
import '../features/customer/product_screen.dart';
import '../features/customer/search_screen.dart';
import '../features/owner/bulk_price_screen.dart';
import '../features/owner/categories_screen.dart';
import '../features/owner/dashboard_screen.dart';
import '../features/owner/more_screen.dart';
import '../features/owner/owner_shell.dart';
import '../features/owner/product_editor_screen.dart';
import '../features/owner/products_screen.dart';
import '../features/owner/shop_settings_screen.dart';
import '../features/startup/startup_screens.dart';
import 'app_state.dart';
import 'config.dart';

final _rootKey = GlobalKey<NavigatorState>();

/// Where a person lands after startup / login.
String homeFor(Session s, Prefs prefs) {
  if (s.isShopkeeper) return '/owner';
  if (!s.isLoggedIn && !prefs.seenWelcome) return '/welcome';
  return '/shop';
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier(0);
  ref.listen(bootstrapProvider, (_, _) => refresh.value++);
  ref.listen(sessionProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  final router = GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) {
      final loc = state.matchedLocation;
      final boot = ref.read(bootstrapProvider);
      final session = ref.read(sessionProvider);
      if (boot.hasError || (session.hasError && !session.hasValue)) {
        return loc == '/error' ? null : '/error';
      }
      if (!session.hasValue) return loc == '/splash' ? null : '/splash';
      final s = session.requireValue;
      if (loc == '/splash' || loc == '/error') return homeFor(s, ref.read(prefsProvider));
      if (loc.startsWith('/owner') && !s.isShopkeeper) return '/shop';
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/error', builder: (_, _) => const StartupErrorScreen()),
      GoRoute(path: '/welcome', builder: (_, _) => const WelcomeScreen()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/signup', builder: (_, _) => const SignupScreen()),
      GoRoute(path: '/forgot', builder: (_, _) => const ForgotPasswordScreen()),
      GoRoute(path: '/reset-password', builder: (_, _) => const ResetPasswordScreen()),
      GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
      GoRoute(path: '/account', builder: (_, _) => const AccountScreen()),
      GoRoute(
        path: '/shop',
        builder: (_, _) => const CustomerHome(),
        routes: [
          GoRoute(path: 'search', builder: (_, _) => const SearchScreen()),
          GoRoute(
            path: 'c/:id',
            builder: (_, st) => CategoryScreen(categoryId: st.pathParameters['id']!),
          ),
          GoRoute(
            path: 'p/:id',
            builder: (_, st) => ProductScreen(productId: st.pathParameters['id']!),
          ),
        ],
      ),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => OwnerShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [GoRoute(path: '/owner', builder: (_, _) => const DashboardScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/owner/products', builder: (_, _) => const ProductsScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/owner/more', builder: (_, _) => const MoreScreen())],
          ),
        ],
      ),
      GoRoute(
        path: '/owner/product/:id',
        parentNavigatorKey: _rootKey,
        builder: (_, st) => ProductEditorScreen(
          productId: st.pathParameters['id'] == 'new' ? null : st.pathParameters['id'],
          barcode: st.uri.queryParameters['barcode'],
        ),
      ),
      GoRoute(path: '/owner/categories', parentNavigatorKey: _rootKey, builder: (_, _) => const CategoriesScreen()),
      GoRoute(path: '/owner/bulk-price', parentNavigatorKey: _rootKey, builder: (_, _) => const BulkPriceScreen()),
      GoRoute(path: '/owner/shop', parentNavigatorKey: _rootKey, builder: (_, _) => const ShopSettingsScreen()),
    ],
  );
  ref.onDispose(router.dispose);

  // Password-reset email link → open the "set new password" screen.
  if (AppConfig.hasBackend) {
    ref.listen(bootstrapProvider, (_, next) {
      if (!next.hasValue) return;
      final sub = Supabase.instance.client.auth.onAuthStateChange.listen((e) {
        if (e.event == AuthChangeEvent.passwordRecovery) router.go('/reset-password');
      }, onError: (_) {});
      ref.onDispose(sub.cancel);
    }, fireImmediately: true);
  }
  return router;
});
