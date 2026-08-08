import 'package:flutter/material.dart';

import '../data/daily_puzzle.dart';
import '../data/progress_store.dart';
import '../models/level.dart';
import '../theme/app_colors.dart';
import 'game_screen.dart';

/// Fetches today's featured puzzle (see [fetchDailyPuzzleLevel]) and hands
/// off to [GameScreen] once it's loaded — the same puzzle for every player
/// today, solved through the exact same interpreter/points/leaderboard
/// machinery as any other puzzle. Loading/error states mirror GameScreen's
/// own lazy-content-fetch screen so the two don't look like different
/// features.
class DailyChallengeScreen extends StatefulWidget {
  const DailyChallengeScreen({super.key});

  @override
  State<DailyChallengeScreen> createState() => _DailyChallengeScreenState();
}

class _DailyChallengeScreenState extends State<DailyChallengeScreen> {
  late Future<(Level, bool alreadySolved)> _levelFuture = _load();

  // Whether the daily puzzle is already in the completed set matters here
  // in a way it doesn't for any other entry point: Campaign/Community
  // Puzzles/a past daily all reuse the same catalog, so today's puzzle may
  // well be one the player already solved elsewhere — GameScreen would
  // otherwise drop that old winning program straight into the functions
  // (see startBlank below).
  Future<(Level, bool)> _load() async {
    final level = await fetchDailyPuzzleLevel();
    final completed = await ProgressStore().loadCompleted();
    return (level, completed.contains(level.id));
  }

  void _retry() {
    setState(() {
      _levelFuture = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(Level, bool)>(
      future: _levelFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            backgroundColor: AppColors.background,
            body: Center(
              child: CircularProgressIndicator(color: AppColors.accent),
            ),
          );
        }

        final data = snapshot.data;
        if (data == null) {
          return Scaffold(
            backgroundColor: AppColors.background,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              iconTheme: const IconThemeData(color: Colors.white),
            ),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      color: Colors.white.withValues(alpha: 0.4),
                      size: 40,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      "Could not load today's puzzle.\n${snapshot.error}",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _retry,
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accent),
                      child:
                          const Text('Retry', style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final (level, alreadySolved) = data;
        return GameScreen(levels: [level], startBlank: alreadySolved);
      },
    );
  }
}
