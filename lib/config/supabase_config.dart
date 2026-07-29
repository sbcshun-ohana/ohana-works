/// Supabase プロジェクトへの接続情報。
///
/// ビルド時に `--dart-define=APP_ENV=production` を指定すると本番環境に接続する。
/// 未指定時はステージング環境(既定)。APP_MODE と同様の dart-define 方式。
class SupabaseConfig {
  SupabaseConfig._();

  static const String _appEnv =
      String.fromEnvironment('APP_ENV', defaultValue: 'staging');

  static const String _stagingUrl = 'https://ulzachwkkyrvmxfzktio.supabase.co';
  static const String _stagingPublishableKey =
      'sb_publishable_yHNhCU85vkfF-oIaP3lwUA_gYnU5HGx';

  static const String _productionUrl = 'https://wdsziqxvmhwbdyfeiame.supabase.co';
  static const String _productionPublishableKey =
      'sb_publishable_U-MSJ6anqJ48iqdpDu-g9A_BzUNR0HI';

  static const String url =
      _appEnv == 'production' ? _productionUrl : _stagingUrl;
  static const String publishableKey =
      _appEnv == 'production' ? _productionPublishableKey : _stagingPublishableKey;
}
