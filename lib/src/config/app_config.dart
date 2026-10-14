import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConfig {
  AppConfig._();
  static late final SupabaseClient supabase;

  static String get baseUrl => _getBaseUrl();

  static Future<void> init() async {
    await Supabase.initialize(
      url: dotenv.get('SUPABASE_URL', fallback: 'https://YOUR-PROJECT.supabase.co'),
      publishableKey: dotenv.get('SUPABASE_ANON_KEY', fallback: 'YOUR-ANON-KEY'),
    );
    supabase = Supabase.instance.client;

  }

  static String _getBaseUrl() {
    return dotenv.get('API_BASE_URL', fallback: 'https://api.example.com');
  }
}
