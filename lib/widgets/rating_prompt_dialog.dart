import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/rating_prompt_store.dart';
import '../theme/app_colors.dart';

const _appStoreId = '6792399726';

/// Opens the App Store's write-a-review flow for this app directly — used
/// by both the auto-triggered [_RatingPromptDialog] and the "Rate this
/// game" button in the About screen.
Future<void> openAppStoreReview() async {
  final uri = Uri.parse(
    'https://apps.apple.com/app/id$_appStoreId?action=write-review',
  );
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

/// Shows the rate-the-game prompt if [RatingPromptStore.shouldShow] says
/// it's due for the given number of solved puzzles. Safe to call after any
/// completion-count refresh — it's a no-op when not due.
Future<void> maybeShowRatingPrompt(
    BuildContext context, int completedCount) async {
  final store = RatingPromptStore();
  if (!await store.shouldShow(completedCount)) return;
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (context) => const _RatingPromptDialog(),
  );
}

class _RatingPromptDialog extends StatelessWidget {
  const _RatingPromptDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppColors.panelBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.star_rounded, color: AppColors.star, size: 44),
            const SizedBox(height: 14),
            const Text(
              'Enjoying Robozzle?',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "If you're having fun with the puzzles, a quick rating "
              'helps a lot!',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  await RatingPromptStore().recordRated();
                  await openAppStoreReview();
                  if (context.mounted) Navigator.of(context).pop();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Rate now',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () async {
                await RatingPromptStore().recordShown();
                if (context.mounted) Navigator.of(context).pop();
              },
              child: Text(
                'Not now',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
