import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:metro_shift_roster/core/network/supabase_client.dart';

class AppUpdateInfo {
  final String latestVersion;
  final String minVersion;
  final String updateUrl;
  final String releaseNotes;
  final bool forceUpdate;

  AppUpdateInfo({
    required this.latestVersion,
    required this.minVersion,
    required this.updateUrl,
    required this.releaseNotes,
    required this.forceUpdate,
  });
}

class AppUpdateService {
  static const String currentAppVersion = "1.0.0";

  static Future<AppUpdateInfo?> checkForUpdate() async {
    try {
      String platform = 'android';
      if (kIsWeb) {
        platform = 'web';
      } else if (Platform.isIOS) {
        platform = 'ios';
      }

      final res = await SupabaseService.client
          .from('app_versions')
          .select()
          .eq('platform', platform)
          .maybeSingle();

      if (res == null) return null;

      final latest = res['latest_version'] as String;
      final min = res['min_required_version'] as String;

      if (_isVersionNewer(latest, currentAppVersion)) {
        return AppUpdateInfo(
          latestVersion: latest,
          minVersion: min,
          updateUrl: res['update_url'] as String,
          releaseNotes: res['release_notes'] as String? ??
              'Bug fixes and performance improvements.',
          forceUpdate: res['force_update'] as bool? ?? false,
        );
      }
    } catch (_) {}
    return null;
  }

  static bool _isVersionNewer(String remote, String local) {
    List<int> r = remote.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    List<int> l = local.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    for (int i = 0; i < r.length && i < l.length; i++) {
      if (r[i] > l[i]) return true;
      if (r[i] < l[i]) return false;
    }
    return false;
  }

  static void showUpdateDialog(BuildContext context, AppUpdateInfo info) {
    showDialog(
      context: context,
      barrierDismissible: !info.forceUpdate,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.system_update_rounded, color: Color(0xFF1E3A8A)),
            SizedBox(width: 8),
            Text('App Update Available'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('A new version (v${info.latestVersion}) is available.'),
            const SizedBox(height: 8),
            const Text('What’s New:',
                style: TextStyle(fontWeight: FontWeight.bold)),
            Text(info.releaseNotes,
                style: const TextStyle(fontSize: 13, color: Colors.black87)),
            if (info.forceUpdate) ...[
              const SizedBox(height: 12),
              const Text(
                'This is a required update to continue using the application.',
                style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                    fontSize: 12),
              ),
            ]
          ],
        ),
        actions: [
          if (!info.forceUpdate)
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Later'),
            ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E3A8A)),
            onPressed: () async {
              final uri = Uri.parse(info.updateUrl);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
            child:
                const Text('Update Now', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
