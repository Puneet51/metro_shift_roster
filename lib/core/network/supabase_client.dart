import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  static Future<void> initialize() async {
    // 1. Attempt to load .env safely
    try {
      if (!dotenv.isInitialized) {
        await dotenv.load(fileName: ".env");
      }
    } catch (_) {
      // Continue; configuration can still be supplied via dart-define or fallback.
    }

    // 2. Read priority: --dart-define -> .env
    // Web/GitHub Pages can use build-time dart-define values even when .env
    // is not available at runtime.
    final String supabaseUrl =
        const String.fromEnvironment('SUPABASE_URL').isNotEmpty
            ? const String.fromEnvironment('SUPABASE_URL')
            : (dotenv.maybeGet('SUPABASE_URL') ?? '');

    final String supabaseAnonKey =
        const String.fromEnvironment('SUPABASE_ANON_KEY').isNotEmpty
            ? const String.fromEnvironment('SUPABASE_ANON_KEY')
            : (dotenv.maybeGet('SUPABASE_ANON_KEY') ?? '');

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
