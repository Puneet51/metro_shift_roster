import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class MandatoryUpdateScreen extends StatelessWidget {
  final String updateUrl;
  final String description;

  const MandatoryUpdateScreen({
    super.key,
    required this.updateUrl,
    required this.description,
  });

  Future<void> _openStore(BuildContext context) async {
    final cleanUrl = updateUrl.trim();
    final Uri? uri = Uri.tryParse(cleanUrl);

    if (uri == null || (!uri.isScheme('http') && !uri.isScheme('https'))) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Invalid update URL: $cleanUrl'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    try {
      // Direct external launch forces the phone's browser/download manager to take over
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!launched) {
        // Fallback to platform default if external intent was intercepted
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not launch update link: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // Prevents closing the update barrier
      child: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(
                Icons.system_update_rounded,
                size: 80,
                color: Color(0xFF1E3A8A),
              ),
              const SizedBox(height: 24),
              const Text(
                'Update Required',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E3A8A),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                description.isNotEmpty
                    ? description
                    : 'A critical update is required to continue using the Namma Metro Shift Roster app.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black87),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E3A8A),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () => _openStore(context),
                child: const Text(
                  'Update Now',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
