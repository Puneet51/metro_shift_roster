import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  // Hardcoded project fallbacks so Web/PWA does not crash if .env fails to load via HTTP
  static const String _defaultSupabaseUrl =
      'https://your-project-id.supabase.co'; // <-- Paste from your .env
  static const String _defaultSupabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...'; // <-- Paste from your .env

  static Future<void> initialize() async {
    // 1. Attempt to load .env safely
    try {
      if (!dotenv.isInitialized) {
        await dotenv.load(fileName: ".env");
      }
    } catch (_) {
      // Continue; configuration can still be supplied via dart-define or fallback.
    }

    // 2. Read priority: .env -> --dart-define -> Hardcoded fallback
    String supabaseUrl =
        dotenv.maybeGet('SUPABASE_URL') ??
        const String.fromEnvironment('SUPABASE_URL');
    if (supabaseUrl.isEmpty) {
      supabaseUrl = _defaultSupabaseUrl;
    }

    String supabaseAnonKey =
        dotenv.maybeGet('SUPABASE_ANON_KEY') ??
        const String.fromEnvironment('SUPABASE_ANON_KEY');
    if (supabaseAnonKey.isEmpty) {
      supabaseAnonKey = _defaultSupabaseAnonKey;
    }

    if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
      throw Exception(
        'Supabase configuration missing: Provide SUPABASE_URL and SUPABASE_ANON_KEY '
        'in .env or via --dart-define flags.',
      );
    }

    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  }

  static SupabaseClient get client => Supabase.instance.client;
}
