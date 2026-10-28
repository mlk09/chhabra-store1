import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../data/backend.dart';
import '../data/demo/demo_backend.dart';
import '../data/local/local_store.dart';
import '../data/models/catalog.dart';
import '../data/models/category.dart';
import '../data/models/member.dart';
import '../data/models/product.dart';
import '../data/models/shop.dart';
import '../data/supabase/supabase_backend.dart';
import 'config.dart';
import 'i18n.dart';

// ── Startup ──────────────────────────────────────────────────────────────────

/// Opens local storage and connects to Supabase, each with a timeout, so the
/// app can never hang on a blank splash screen.
final bootstrapProvider = FutureProvider<LocalStore>((ref) async {
  final store = await LocalStore.open().timeout(const Duration(seconds: 6));
  if (AppConfig.hasBackend) {
    try {
      await Supabase.initialize(
        url: AppConfig.supabaseUrl,
        publishableKey: AppConfig.supabaseAnonKey,
      ).timeout(const Duration(seconds: 8));
    } on TimeoutException {
      throw const AppException(
        'Could not connect to the shop server in time.',
        'दुकान के सर्वर से समय पर कनेक्ट नहीं हो पाया।',
      );
    } catch (e) {
      // Already initialised (hot restart / retry) is fine.
      if (!e.toString().contains('already initialized')) rethrow;
    }
  }
  return store;
});

final localStoreProvider = Provider<LocalStore>((ref) => ref.watch(bootstrapProvider).requireValue);

// ── Preferences ──────────────────────────────────────────────────────────────

class Prefs {
  const Prefs({this.language = AppLanguage.en, this.themeMode = ThemeMode.dark, this.seenWelcome = false});
  final AppLanguage language;
  final ThemeMode themeMode;
  final bool seenWelcome;
}

class PrefsController extends Notifier<Prefs> {
  LocalStore? get _store => ref.read(bootstrapProvider).value;

  @override
  Prefs build() {
    final s = ref.watch(bootstrapProvider).value;
    if (s == null) return const Prefs();
    return Prefs(
      language: s.pref<String>('lang') == 'hi' ? AppLanguage.hi : AppLanguage.en,
      themeMode: switch (s.pref<String>('theme')) {
        'light' => ThemeMode.light,
        'system' => ThemeMode.system,
        _ => ThemeMode.dark, // premium dark look by default
      },
      seenWelcome: s.pref<bool>('seenWelcome') ?? false,
    );
  }

  void setLanguage(AppLanguage l) {
    _store?.setPref('lang', l.name);
    state = Prefs(language: l, themeMode: state.themeMode, seenWelcome: state.seenWelcome);
  }

  void setTheme(ThemeMode m) {
    _store?.setPref('theme', m.name);
    state = Prefs(language: state.language, themeMode: m, seenWelcome: state.seenWelcome);
  }

  void markWelcomeSeen() {
    _store?.setPref('seenWelcome', true);
    state = Prefs(language: state.language, themeMode: state.themeMode, seenWelcome: true);
  }
}

final prefsProvider = NotifierProvider<PrefsController, Prefs>(PrefsController.new);

// ── Session: who is using the app, and against which backend ─────────────────

class Session {
  const Session({required this.backend, this.user, this.membership = Membership.customer});

  final Backend backend;
  final AppUser? user;
  final Membership membership;

  bool get isDemo => backend.isDemo;
  bool get isLoggedIn => user != null;
  bool get isShopkeeper => membership.isShopkeeper;
  bool can(String perm) => membership.can(perm);
}

class SessionController extends AsyncNotifier<Session> {
  StreamSubscription<AppUser?>? _authSub;
  SupabaseBackend? _live;

  @override
  Future<Session> build() async {
    await ref.watch(bootstrapProvider.future);
    ref.onDispose(() => _authSub?.cancel());
    if (!AppConfig.hasBackend) {
      return Session(backend: DemoBackend(asShopkeeper: false));
    }
    final live = _live ??= SupabaseBackend(AppConfig.shopSlug);
    _authSub ??= live.authChanges().skip(1).listen((_) => _reloadLive());
    return _liveSession(live);
  }

  Future<Session> _liveSession(SupabaseBackend live) async {
    final user = live.currentUser;
    if (user == null) return Session(backend: live);
    try {
      return Session(backend: live, user: user, membership: await live.membership());
    } catch (_) {
      // Offline at startup: open as customer; shopkeeper tools appear once online.
      return Session(backend: live, user: user);
    }
  }

  Future<void> _reloadLive() async {
    final live = _live;
    if (live == null || state.value?.isDemo == true) return;
    state = AsyncData(await _liveSession(live));
  }

  /// Call after login/sign-up so the role is known before navigating.
  Future<void> refresh() => _reloadLive();

  void startDemo({required bool asShopkeeper}) {
    final backend = DemoBackend(asShopkeeper: asShopkeeper);
    state = AsyncData(
      Session(
        backend: backend,
        user: backend.currentUser,
        membership: asShopkeeper ? Membership.owner : Membership.customer,
      ),
    );
  }

  Future<void> exitDemo() async {
    if (!AppConfig.hasBackend) {
      state = AsyncData(Session(backend: DemoBackend(asShopkeeper: false)));
      return;
    }
    state = AsyncData(await _liveSession(_live!));
  }

  Future<void> signOut() async {
    final s = state.value;
    if (s == null) return;
    if (s.isDemo) return exitDemo();
    await ref.read(localStoreProvider).clearCatalogs(); // cost prices must not stay on the phone
    await s.backend.signOut();
    state = AsyncData(Session(backend: s.backend));
  }
}

final sessionProvider = AsyncNotifierProvider<SessionController, Session>(SessionController.new);

/// Shortcut for screens: the backend of the current session.
final backendProvider = Provider<Backend>((ref) => ref.watch(sessionProvider).requireValue.backend);

// ── Catalog ──────────────────────────────────────────────────────────────────

/// Products, categories and shop details. Opens instantly from the on-device
/// copy, then refreshes from the server in the background.
class CatalogController extends AsyncNotifier<Catalog> {
  late Session _session;

  bool get _staffView => _session.isShopkeeper;
  bool get _withCosts => _session.can(Perm.prices) || _session.can(Perm.reports);
  String get _cacheKey => _staffView ? 'staff' : 'public';

  @override
  Future<Catalog> build() async {
    _session = await ref.watch(sessionProvider.future);
    final backend = _session.backend;
    if (!backend.isDemo) {
      final cached = ref.read(localStoreProvider).readCatalog(_cacheKey);
      if (cached != null) {
        unawaited(Future.microtask(() => refresh(silent: true)));
        return cached;
      }
    }
    final fresh = await backend.loadCatalog(staffView: _staffView, withCosts: _withCosts);
    _save(fresh);
    return fresh;
  }

  /// Download the latest catalog. With [silent], failures keep the old data.
  Future<void> refresh({bool silent = false}) async {
    try {
      final fresh = await _session.backend.loadCatalog(staffView: _staffView, withCosts: _withCosts);
      if (!ref.mounted) return;
      state = AsyncData(fresh);
      _save(fresh);
    } catch (e, st) {
      if (!ref.mounted) return;
      if (!silent || state.value == null) state = AsyncError(e, st);
    }
  }

  void _save(Catalog c) {
    if (_session.isDemo) return;
    ref.read(localStoreProvider).writeCatalog(_cacheKey, c);
  }

  void _update(Catalog Function(Catalog c) change) {
    final current = state.value;
    if (current == null) return;
    final next = change(current);
    state = AsyncData(next);
    _save(next);
  }

  Future<Product> saveProduct(Product p, {ProductPhoto? photo, Set<String>? stockChanged}) async {
    final saved = await _session.backend.saveProduct(
      p,
      photo: photo,
      withCosts: _session.can(Perm.prices),
      stockChanged: stockChanged,
    );
    _update((c) => c.withProduct(saved));
    return saved;
  }

  Future<void> deleteProduct(String id) async {
    await _session.backend.deleteProduct(id);
    _update((c) => c.withoutProduct(id));
  }

  Future<void> setProductActive(Product p, bool active) async {
    await saveProduct(p.copyWith(isActive: active), stockChanged: const {});
  }

  Future<void> saveCategory(Category cat) async {
    final saved = await _session.backend.saveCategory(cat);
    _update((c) => c.withCategory(saved));
  }

  Future<void> deleteCategory(String id) async {
    await _session.backend.deleteCategory(id);
    _update((c) => c.withoutCategory(id));
  }

  Future<int> bulkUpdatePrices({
    required double percent,
    String? categoryId,
    String applyTo = 'both',
    String rounding = 'rupee',
  }) async {
    final n = await _session.backend.bulkUpdatePrices(
      percent: percent,
      categoryId: categoryId,
      applyTo: applyTo,
      rounding: rounding,
    );
    await refresh();
    return n;
  }

  Future<void> updateShop(Shop shop) async {
    final saved = await _session.backend.updateShop(shop);
    _update((c) => c.copyWith(shop: saved));
  }
}

final catalogProvider = AsyncNotifierProvider<CatalogController, Catalog>(CatalogController.new);
