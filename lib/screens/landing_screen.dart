import 'package:flutter/material.dart';

import '../data/auth_manager.dart';
import '../data/level_catalog.dart';
import '../data/points.dart';
import '../data/progress_store.dart';
import '../theme/app_colors.dart';
import 'auth/pseudonym_screen.dart';
import 'auth/sign_in_screen.dart';
import 'coming_soon_screen.dart';
import 'home_screen.dart';
import 'leaderboard_screen.dart';
import 'tutorial_screen.dart';

/// The app's true entry point: a menu of game modes. "Community Puzzles"
/// and "Campaign" are wired up so far — both open [HomeScreen], the
/// browser for the scraped Robozzle catalog, narrowed by author for
/// Campaign. The rest are placeholders until they're built.
class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> {
  late Future<int> _pointsFuture = _loadPoints();

  Future<int> _loadPoints() async {
    final completedIds = await ProgressStore().loadCompleted();
    final levels = await loadCatalogLevels();
    return totalPoints(completedIds, levels);
  }

  void _refreshPoints() {
    setState(() {
      _pointsFuture = _loadPoints();
    });
  }

  Future<void> _openHomeScreen(
    BuildContext context, {
    String title = 'Community Puzzles',
    Set<String>? authorFilter,
    bool allowSortChoice = true,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => HomeScreen(
          title: title,
          authorFilter: authorFilter,
          allowSortChoice: allowSortChoice,
        ),
      ),
    );
    _refreshPoints();
  }

  void _openComingSoon(BuildContext context, String title) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ComingSoonScreen(title: title)),
    );
  }

  /// Leaderboard/Editor require an account: sign in with Apple if needed,
  /// then pick a pseudonym on first-ever sign in, before continuing on.
  /// Returns whether the gate was passed.
  Future<bool> _ensureAuthenticated(BuildContext context) async {
    final authManager = AuthManager.instance;
    await authManager.restoreSession();

    if (!context.mounted) return false;
    if (!authManager.isConnected) {
      final outcome = await Navigator.of(context).push<ManageUserOutcome>(
        MaterialPageRoute(builder: (_) => const SignInScreen()),
      );
      if (outcome == null || !context.mounted) return false;
    }

    if (authManager.needsPseudonym) {
      final saved = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const PseudonymScreen()),
      );
      if (saved != true || !context.mounted) return false;
    }

    return true;
  }

  Future<void> _openGatedComingSoon(BuildContext context, String title) async {
    final ok = await _ensureAuthenticated(context);
    if (!ok || !context.mounted) return;
    _openComingSoon(context, title);
  }

  Future<void> _openLeaderboard(BuildContext context) async {
    final ok = await _ensureAuthenticated(context);
    if (!ok || !context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LeaderboardScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Robozzle',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 32,
                    ),
                  ),
                  FutureBuilder<int>(
                    future: _pointsFuture,
                    builder: (context, snapshot) {
                      final points = snapshot.data;
                      if (points == null) return const SizedBox.shrink();
                      return _PointsBadge(points: points);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Choose a mode',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 32),
              Expanded(
                child: ListView(
                  children: [
                    _LandingMenuButton(
                      icon: Icons.school_rounded,
                      label: 'Tutorials',
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const TutorialScreen(),
                          ),
                        );
                        _refreshPoints();
                      },
                    ),
                    const SizedBox(height: 12),
                    _LandingMenuButton(
                      icon: Icons.flag_rounded,
                      label: 'Campaign',
                      // These puzzles also stay visible under Community
                      // Puzzles — this only narrows which screen shows
                      // them, it doesn't remove them from the full catalog.
                      onTap: () => _openHomeScreen(
                        context,
                        title: 'Campaign',
                        authorFilter: {
                          'igoro',
                          'blake',
                          'markbyers',
                          'snydej',
                          'stingray',
                        },
                        // Always sorted by difficulty — no Sort-by choice.
                        allowSortChoice: false,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _LandingMenuButton(
                      icon: Icons.public_rounded,
                      label: 'Community Puzzles',
                      onTap: () => _openHomeScreen(context),
                    ),
                    const SizedBox(height: 12),
                    _LandingMenuButton(
                      icon: Icons.edit_rounded,
                      label: 'Editor',
                      onTap: () => _openGatedComingSoon(context, 'Editor'),
                    ),
                    const SizedBox(height: 12),
                    _LandingMenuButton(
                      icon: Icons.leaderboard_rounded,
                      label: 'Leaderboard',
                      onTap: () => _openLeaderboard(context),
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

class _PointsBadge extends StatelessWidget {
  final int points;

  const _PointsBadge({required this.points});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.panelBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star_rounded, color: AppColors.star, size: 16),
          const SizedBox(width: 5),
          Text(
            '$points',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _LandingMenuButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _LandingMenuButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.panelBorder),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.accent, size: 26),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 17,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: Colors.white.withValues(alpha: 0.4),
            ),
          ],
        ),
      ),
    );
  }
}
