import 'package:flutter/material.dart';

import '../data/leaderboard.dart';
import '../theme/app_colors.dart';

/// Shows the full leaderboard fetched from `robozzle-leaderboard`. The list
/// always scrolls freely; the player's own row is highlighted in red, and if
/// it wouldn't otherwise fit in the visible area it's pinned as a static row
/// at the bottom so the player can always see their rank.
class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  static const double _rowHeight = 56;

  late Future<LeaderboardResult> _future = fetchLeaderboard();

  void _retry() {
    setState(() => _future = fetchLeaderboard());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Leaderboard', style: TextStyle(color: Colors.white)),
      ),
      body: SafeArea(
        child: FutureBuilder<LeaderboardResult>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(
                child: CircularProgressIndicator(color: AppColors.accent),
              );
            }
            if (snapshot.hasError) {
              return _ErrorView(error: snapshot.error, onRetry: _retry);
            }

            final result = snapshot.data!;
            if (result.entries.isEmpty) {
              return Center(
                child: Text(
                  'No scores yet.',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
                ),
              );
            }

            return _LeaderboardList(result: result, rowHeight: _rowHeight);
          },
        ),
      ),
    );
  }
}

class _LeaderboardList extends StatelessWidget {
  final LeaderboardResult result;
  final double rowHeight;

  const _LeaderboardList({required this.result, required this.rowHeight});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final userIndex =
            result.entries.indexWhere((e) => e.rank == result.userRank);
        final userEntry = userIndex == -1 ? null : result.entries[userIndex];
        final contentHeight = result.entries.length * rowHeight;
        final userRowOffset = userIndex * rowHeight;
        // Only pin a footer when the user's own row wouldn't otherwise be
        // visible without scrolling — a duplicate footer is redundant when
        // the whole list already fits on screen.
        final needsPin = userEntry != null &&
            contentHeight > constraints.maxHeight &&
            userRowOffset + rowHeight > constraints.maxHeight;
        final pinnedEntry = needsPin ? userEntry : null;

        return Column(
          children: [
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: result.entries.length,
                itemExtent: rowHeight,
                itemBuilder: (context, index) {
                  final entry = result.entries[index];
                  return _LeaderboardRow(
                    entry: entry,
                    isCurrentUser: entry.rank == result.userRank,
                  );
                },
              ),
            ),
            if (pinnedEntry != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: const BoxDecoration(
                  color: AppColors.panel,
                  border: Border(top: BorderSide(color: AppColors.panelBorder)),
                ),
                child: SafeArea(
                  top: false,
                  child: _LeaderboardRow(entry: pinnedEntry, isCurrentUser: true),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _LeaderboardRow extends StatelessWidget {
  final LeaderboardEntry entry;
  final bool isCurrentUser;

  const _LeaderboardRow({required this.entry, required this.isCurrentUser});

  @override
  Widget build(BuildContext context) {
    final color = isCurrentUser ? Colors.redAccent : Colors.white;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Text(
              '${entry.rank}',
              style: TextStyle(
                color: color.withValues(alpha: isCurrentUser ? 1 : 0.6),
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ),
          Expanded(
            child: Text(
              entry.pseudonym,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontWeight: isCurrentUser ? FontWeight.bold : FontWeight.w500,
                fontSize: 16,
              ),
            ),
          ),
          Text(
            '${entry.score}',
            style: TextStyle(
              color: color,
              fontWeight: isCurrentUser ? FontWeight.bold : FontWeight.w500,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final Object? error;
  final VoidCallback onRetry;

  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
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
              'Could not load the leaderboard.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent),
              child: const Text('Retry', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}
