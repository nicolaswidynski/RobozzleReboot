import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_colors.dart';

const _robozzleUrl = 'https://robozzle.com/';

/// Static credits/rules screen: attributes the original Robozzle game and
/// spells out the one behavior rule (no inappropriate pseudonyms/puzzle
/// titles) that can get a player permanently banned.
class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  late final TapGestureRecognizer _linkRecognizer = TapGestureRecognizer()
    ..onTap = _openRobozzleSite;

  @override
  void dispose() {
    _linkRecognizer.dispose();
    super.dispose();
  }

  Future<void> _openRobozzleSite() async {
    final uri = Uri.parse(_robozzleUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bodyStyle = TextStyle(
      color: Colors.white.withValues(alpha: 0.85),
      fontSize: 15,
      height: 1.5,
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('About', style: TextStyle(color: Colors.white)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RichText(
                text: TextSpan(
                  style: bodyStyle,
                  children: [
                    const TextSpan(
                      text: 'Robozzle is an original game from Igor '
                          'Ostrovsky and other contributors (',
                    ),
                    TextSpan(
                      text: 'robozzle.com',
                      style: const TextStyle(
                        color: AppColors.accent,
                        decoration: TextDecoration.underline,
                      ),
                      recognizer: _linkRecognizer,
                    ),
                    const TextSpan(text: ').'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Robozzle Reboot is a fresh implementation developed with '
                'the agreement of the original author.',
                style: bodyStyle,
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.panel,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.panelBorder),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.white.withValues(alpha: 0.7),
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Any inappropriate behavior (pseudo, puzzle title) '
                        'will result in permanent ban.',
                        style: bodyStyle,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
