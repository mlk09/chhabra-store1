/// Build-time configuration, injected with `--dart-define-from-file=.env`.
/// Only PUBLIC values belong here. Secrets live in Supabase / GitHub Secrets.
class AppConfig {
  const AppConfig._();

  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const shopSlug = String.fromEnvironment('SHOP_SLUG', defaultValue: 'chhabra-general-store');

  /// Public web address of the app (used in password-reset emails).
  static const webAppUrl = String.fromEnvironment('WEB_APP_URL');

  static const appName = 'Chhabra General Store';
  static const appNameHi = 'छाबड़ा जनरल स्टोर';

  /// False when the app was built without Supabase details → Demo-only build.
  static bool get hasBackend => supabaseUrl.startsWith('https://') && supabaseAnonKey.length > 20;

  static String imageUrl(String path) => '$supabaseUrl/storage/v1/object/public/product-images/$path';
}
