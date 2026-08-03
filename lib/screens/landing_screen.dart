import 'package:flutter/material.dart';

import '../data/auth_manager.dart';
import '../data/catalog_refresher.dart';
import '../data/leaderboard_sync.dart';
import '../data/level_catalog.dart';
import '../data/points.dart';
import '../data/progress_store.dart';
import '../theme/app_colors.dart';
import 'about_screen.dart';
import 'auth/pseudonym_screen.dart';
import 'auth/sign_in_screen.dart';
import 'editor/editor_home_screen.dart';
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
  // Campaign and Community Puzzles partition the catalog rather than
  // overlapping — a puzzle by one of these authors only ever shows up
  // under Campaign, never also under Community Puzzles.
  static const _campaignAuthors = {'igoro', 'blake', 'markbyers', 'wido'};

  late Future<int> _pointsFuture = _loadPoints();

  @override
  void initState() {
    super.initState();
    // The catalog refreshes in the background here on every launch (once
    // daily; see CatalogRefresher's own throttle) and again on pull to
    // refresh from HomeScreen — a puzzle may have been re-rated or removed
    // since, so the badge needs to recompute whenever that happens, not
    // just when we're navigated back to. Unconditional, unlike the
    // leaderboard sync below: browsing/scoring never requires an account,
    // so refreshing puzzle metadata shouldn't either.
    CatalogRefresher.instance.addListener(_refreshPoints);
    CatalogRefresher.instance.refreshDaily();
    // Loads the stored identity/pseudonym (if any) so the badge can show it
    // without the player first having to open an auth-gated screen.
    // restoreSession() only calls notifyListeners() when it actually changes
    // something (e.g. a silent reconnect) — not when the session was already
    // fine — so this explicit setState is needed to pick up the loaded
    // pseudonym in the common "already signed in" case too.
    AuthManager.instance.addListener(_onAuthChanged);
    AuthManager.instance.restoreSession().then((_) {
      _onAuthChanged();
      // At least once a day, signed in only (this actually needs an
      // account): pushes this device's score/completed puzzles and pulls
      // back the account-wide completed-puzzles superset (see
      // LeaderboardSync) — may grow the local completed set, so the points
      // badge needs a refresh when it actually ran.
      LeaderboardSync.instance.syncIfDue().then((synced) {
        if (synced) _refreshPoints();
      });
    });
  }

  @override
  void dispose() {
    CatalogRefresher.instance.removeListener(_refreshPoints);
    AuthManager.instance.removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    if (mounted) setState(() {});
  }

  // Prefers the server's own score (cached from the last leaderboard sync
  // — see ProgressStore.saveServerScore) once one exists, since the
  // server is authoritative on it; falls back to a local recount only
  // before the first-ever sync (offline/never-signed-in).
  Future<int> _loadPoints() async {
    final serverScore = await ProgressStore().loadServerScore();
    if (serverScore != null) return serverScore;
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
    Set<String>? excludeAuthors,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => HomeScreen(
          title: title,
          authorFilter: authorFilter,
          excludeAuthors: excludeAuthors,
        ),
      ),
    );
    _refreshPoints();
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

  Future<void> _openEditor(BuildContext context) async {
    final ok = await _ensureAuthenticated(context);
    if (!ok || !context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const EditorHomeScreen()),
    );
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
                  const Row(
                    children: [
                      // The same icon used for the robot sprite in-game
                      // (see RobotGrid), so the title reads as "this app's
                      // robot" rather than a generic logo.
                      Icon(
                        Icons.navigation_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Robozzle',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 32,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (AuthManager.instance.pseudonym case final pseudonym?) ...[
                        Text(
                          pseudonym,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
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
                      onTap: () => _openHomeScreen(
                        context,
                        title: 'Campaign',
                        authorFilter: _campaignAuthors,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _LandingMenuButton(
                      icon: Icons.public_rounded,
                      label: 'Community Puzzles',
                      onTap: () => _openHomeScreen(
                        context,
                        excludeAuthors: _campaignAuthors,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _LandingMenuButton(
                      icon: Icons.edit_rounded,
                      label: 'Editor',
                      onTap: () => _openEditor(context),
                    ),
                    const SizedBox(height: 12),
                    _LandingMenuButton(
                      icon: Icons.leaderboard_rounded,
                      label: 'Leaderboard',
                      onTap: () => _openLeaderboard(context),
                    ),
                    const SizedBox(height: 12),
                    _LandingMenuButton(
                      icon: Icons.info_outline_rounded,
                      label: 'About',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const AboutScreen(),
                        ),
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
