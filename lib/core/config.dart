/// Build-time configuration, injected with `--dart-define-from-file=.env`.
/// Only PUBLIC values belong here. Secrets live in Supabase / GitHub Secrets.
class AppConfig {
  const AppConfig._();

  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// The one shop this app serves. (An empty SHOP_SLUG would turn on the
  /// multi-shop "find your shop" mode — not used for now.)
  static const lockedShopSlug = String.fromEnvironment('SHOP_SLUG', defaultValue: 'chhabra-general-store');
  static bool get isLockedToShop => lockedShopSlug.isNotEmpty;

  /// Public web address of the app (password-reset links, shop links, QR codes).
  static const webAppUrl = String.fromEnvironment('WEB_APP_URL');

  /// Shown before the shop's own details have loaded (splash, startup errors).
  static const appName = String.fromEnvironment('APP_NAME', defaultValue: 'Chhabra General Store');
  static const appNameHi = String.fromEnvironment('APP_NAME_HI', defaultValue: 'छाबड़ा जनरल स्टोर');

  /// False when the app was built without Supabase details → Demo-only build.
  static bool get hasBackend => supabaseUrl.startsWith('https://') && supabaseAnonKey.length > 20;

  static String imageUrl(String path) => '$supabaseUrl/storage/v1/object/public/product-images/$path';

  /// Link that opens one shop directly: `https://…/app/?shop=slug`
  static String shopLink(String slug) => webAppUrl.isEmpty ? '?shop=$slug' : '$webAppUrl?shop=$slug';
}
