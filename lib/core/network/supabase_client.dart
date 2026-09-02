import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  static Future<void> initialize() async {
    // 1. Attempt to load .env safely (may be blocked by web hosting on dotfiles)
    try {
      if (!dotenv.isInitialized) {
        await dotenv.load(fileName: ".env");
      }
    } catch (e) {
      debugPrint('DotEnv load notice: $e');
    }

    // 2. Read from .env first, then fallback to compile-time --dart-define
    final supabaseUrl =
        dotenv.maybeGet('SUPABASE_URL') ??
        const String.fromEnvironment('SUPABASE_URL');

    final supabaseAnonKey =
        dotenv.maybeGet('SUPABASE_ANON_KEY') ??
        const String.fromEnvironment('SUPABASE_ANON_KEY');

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
