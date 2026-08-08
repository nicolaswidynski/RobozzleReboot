import 'package:flutter/material.dart';

import '../data/daily_puzzle.dart';
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
  late Future<Level> _levelFuture = fetchDailyPuzzleLevel();

  void _retry() {
    setState(() {
      _levelFuture = fetchDailyPuzzleLevel();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Level>(
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

        final level = snapshot.data;
        if (level == null) {
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

        return GameScreen(levels: [level]);
      },
    );
  }
}
