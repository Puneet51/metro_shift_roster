import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:metro_shift_roster/features/app_version/presentation/mandatory_update_screen.dart';

class SplashScreen extends StatefulWidget {
  final VoidCallback onCheckComplete;
  const SplashScreen({super.key, required this.onCheckComplete});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _initVersionCheck();
  }

  Future<void> _initVersionCheck() async {
    // Keep splash visible briefly so the logo displays smoothly
    await Future.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;

    final isMandatoryUpdate = await checkAppVersion(context);

    // If update is required, halt flow so MandatoryUpdateScreen stays in place
    if (isMandatoryUpdate) return;

    // Otherwise, signal that version check passed
    if (mounted) {
      widget.onCheckComplete();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Image.asset(
                'assets/images/metro_logo.png',
                width: 110,
                height: 110,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E3A8A),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Icon(
                    Icons.subway_rounded,
                    size: 60,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Metro Shift Roster',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E3A8A),
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 32),
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: Color(0xFF1E3A8A),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<bool> checkAppVersion(BuildContext context) async {
  if (kIsWeb) {
    return false;
  }

  try {
    final String platformName = Platform.isIOS ? 'ios' : 'android';
    final res = await Supabase.instance.client
        .from('app_versions')
        .select()
        .eq('platform', platformName)
        .maybeSingle();

    if (res == null) {
      return false;
    }

    final String minVer =
        (res['min_supported_version'] ??
                res['min_version'] ??
                res['version'] ??
                '1.0.0')
            .toString();
    final bool force =
        (res['is_mandatory'] == true) || (res['force_update'] == true);
    final String url = (res['update_url'] ?? 'https://metroshiftroster.web.app')
        .toString();
    final String desc = (res['description'] ?? res['release_notes'] ?? '')
        .toString();

    // Dynamically reads the installed APK/iOS app version from pubspec.yaml
    final packageInfo = await PackageInfo.fromPlatform();
    final String currentVer = packageInfo.version;

    final bool needsUpdate = isVersionOlder(currentVer, minVer);
    if (force && needsUpdate) {
      if (context.mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (_) =>
                MandatoryUpdateScreen(updateUrl: url, description: desc),
          ),
          (route) => false,
        );
      }
      return true;
    }
  } catch (_) {
    return false;
  }

  return false;
}

bool isVersionOlder(String current, String target) {
  List<int> c = current
      .split('+')
      .first
      .split('.')
      .map((e) => int.tryParse(e) ?? 0)
      .toList();
  List<int> t = target
      .split('+')
      .first
      .split('.')
      .map((e) => int.tryParse(e) ?? 0)
      .toList();
  while (c.length < 3) c.add(0);
  while (t.length < 3) t.add(0);
  for (int i = 0; i < 3; i++) {
    if (c[i] < t[i]) return true;
    if (c[i] > t[i]) return false;
  }
  return false;
}
