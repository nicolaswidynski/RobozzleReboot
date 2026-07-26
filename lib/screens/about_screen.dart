import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/auth_manager.dart';
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
  bool _deleting = false;

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

  // Non-destructive: AuthManager.disconnect() leaves the stored identity
  // and session token in place, so a later sign-in silently reconnects the
  // same account rather than prompting fresh — no confirmation needed.
  void _disconnect() {
    AuthManager.instance.disconnect();
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Disconnected')),
    );
  }

  // Unlike disconnect, this is permanent — the account, pseudonym, and
  // leaderboard entry are all gone server-side, so it needs an explicit
  // confirmation first. Puzzles already published stay in the community
  // catalog — deleting the account doesn't pull them down.
  Future<void> _confirmDeleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.panel,
        title: const Text('Delete account?',
            style: TextStyle(color: Colors.white)),
        content: Text(
          'This permanently deletes your account, pseudonym, and '
          "leaderboard entry. It can't be undone. Puzzles you've already "
          'published stay part of the community catalog.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed == true) await _deleteAccount();
  }

  Future<void> _deleteAccount() async {
    setState(() => _deleting = true);
    try {
      await AuthManager.instance.deleteAccount();
      if (!mounted) return;
      setState(() => _deleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Account deleted')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _deleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete account: $e')),
      );
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
              if (AuthManager.instance.isConnected) ...[
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.panel,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.panelBorder),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          switch (AuthManager.instance.pseudonym) {
                            final pseudonym? => 'Connected as $pseudonym',
                            null => 'Connected',
                          },
                          style: bodyStyle,
                        ),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton(
                        onPressed: _disconnect,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: AppColors.panelBorder),
                        ),
                        child: const Text('Disconnect'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: _deleting ? null : _confirmDeleteAccount,
                    child: _deleting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.redAccent,
                            ),
                          )
                        : const Text('Delete Account',
                            style: TextStyle(color: Colors.redAccent)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
