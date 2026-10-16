import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConfig {
  AppConfig._();
  static late final SupabaseClient supabase;

  static String get baseUrl => _getBaseUrl();

  static Future<void> init() async {
    final url = dotenv.maybeGet('SUPABASE_URL') ?? '';
    final key = dotenv.maybeGet('SUPABASE_PUBLISHABLE_KEY') ??
        dotenv.maybeGet('SUPABASE_ANON_KEY') ??
        '';
    if (!isValidClientConfiguration(url: url, key: key)) {
      throw const FormatException(
          'Configure the Supabase URL and public client key in .env');
    }
    await Supabase.initialize(
      url: url.trim(),
      publishableKey: key.trim(),
    );
    supabase = Supabase.instance.client;
  }

  /// A client build must never be initialized with a service-role/secret key.
  static bool isValidClientConfiguration(
      {required String url, required String key}) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null ||
        uri.host.isEmpty ||
        uri.host.toLowerCase().contains('your-project')) {
      return false;
    }
    if (uri.scheme != 'https' &&
        !(uri.scheme == 'http' &&
            {'localhost', '127.0.0.1', '::1'}.contains(uri.host))) {
      return false;
    }
    final value = key.trim();
    if (value.startsWith('sb_publishable_') && value.length > 25) return true;
    final parts = value.split('.');
    if (parts.length != 3) return false;
    try {
      final claims = jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      return claims is Map<String, dynamic> && claims['role'] == 'anon';
    } on FormatException {
      return false;
    }
  }

  static String _getBaseUrl() {
    return dotenv.get('API_BASE_URL', fallback: 'https://api.example.com');
  }
}
