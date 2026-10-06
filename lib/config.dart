import 'package:intl/intl.dart';

abstract final class AppConfig {
  // Temporary catalog mode. Set USE_TEST_DATA=false to connect to Supabase.
  static const useTestData = bool.fromEnvironment(
    'USE_TEST_DATA',
    defaultValue: true,
  );
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const instagramUsername = 'ge.to.ge';
  static const instagramUrl = 'https://ig.me/m/$instagramUsername';
  static const whatsappNumber = '9647778700244';
  static const whatsappUrl = 'https://wa.me/$whatsappNumber';
  static const brand = 'G2G';
  // Optional bundled asset, shared by the header and generated images.
  static const logoAsset = String.fromEnvironment('LOGO_ASSET');
  static const pageSize = 24;
  static const designsPerImage = 6;
  static const maxUploadBytes = 10 * 1024 * 1024;
  static bool get configured =>
      supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty;
  static String money(int value) =>
      '${NumberFormat('#,###', 'en').format(value)} د.ع';
}
