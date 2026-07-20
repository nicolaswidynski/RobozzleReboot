import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Placeholder destination for landing-page menu items that aren't built
/// yet (Tutorials, Campaign, Editor, Leaderboard).
class ComingSoonScreen extends StatelessWidget {
  final String title;

  const ComingSoonScreen({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(title, style: const TextStyle(color: Colors.white)),
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.construction_rounded,
              color: Colors.white.withValues(alpha: 0.3),
              size: 56,
            ),
            const SizedBox(height: 16),
            Text(
              '$title is coming soon',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
