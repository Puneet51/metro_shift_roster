import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
    await Future.delayed(const Duration(milliseconds: 200));
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
    return const Scaffold(
      backgroundColor: Colors.white,
      body: Center(child: CircularProgressIndicator(color: Color(0xFF1E3A8A))),
    );
  }
}

Future<bool> checkAppVersion(BuildContext context) async {
  if (kIsWeb) {
    debugPrint(
      '[VERSION CHECK] Skipping version check for web browser environment',
    );
    return false;
  }

  try {
    final String platformName = Platform.isIOS ? 'ios' : 'android';
    debugPrint('--- [VERSION CHECK START] ---');
    debugPrint('Checking version for platform: $platformName');

    final res = await Supabase.instance.client
        .from('app_versions')
        .select()
        .eq('platform', platformName)
        .maybeSingle();

    debugPrint('DB Response: $res');

    if (res == null) {
      debugPrint(
        '[VERSION CHECK] No version config found for platform: $platformName',
      );
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

    const String currentVer = '1.0.0';

    final bool needsUpdate = isVersionOlder(currentVer, minVer);
    debugPrint(
      'Current: $currentVer | Target Min: $minVer | Force: $force | NeedsUpdate: $needsUpdate',
    );

    if (force && needsUpdate) {
      debugPrint('[VERSION CHECK] Mandatory update triggered! Navigating...');
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
  } catch (e, stack) {
    debugPrint('[VERSION CHECK ERROR]: $e');
    debugPrint('[VERSION CHECK STACK]: $stack');
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
