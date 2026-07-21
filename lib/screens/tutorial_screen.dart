import 'package:flutter/material.dart';

import '../data/progress_store.dart';
import '../data/tutorial_levels.dart';
import '../models/level.dart';
import '../theme/app_colors.dart';
import 'game_screen.dart';

/// Lists the hand-authored tutorial levels (see tutorial_levels.dart), each
/// teaching one mechanic in order: movement, loops, then conditions/paint.
/// Opens straight into [GameScreen] with the full tutorial list, so "Next"
/// walks through all three in order.
class TutorialScreen extends StatefulWidget {
  const TutorialScreen({super.key});

  @override
  State<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends State<TutorialScreen> {
  final ProgressStore _progressStore = ProgressStore();
  Set<String> _completedIds = const {};

  @override
  void initState() {
    super.initState();
    _refreshCompleted();
  }

  Future<void> _refreshCompleted() async {
    final ids = await _progressStore.loadCompleted();
    if (!mounted) return;
    setState(() => _completedIds = ids);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (Navigator.of(context).canPop())
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: InkWell(
                        onTap: () => Navigator.of(context).pop(),
                        customBorder: const CircleBorder(),
                        child: const Padding(
                          padding: EdgeInsets.all(6),
                          child: Icon(Icons.arrow_back_rounded,
                              color: Colors.white70, size: 24),
                        ),
                      ),
                    ),
                  const Text(
                    'Tutorials',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 26,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Learn the basics, one step at a time',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 18),
              Expanded(
                child: ListView.separated(
                  itemCount: tutorialLevels.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final level = tutorialLevels[i];
                    return _TutorialCard(
                      level: level,
                      completed: _completedIds.contains(level.id),
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => GameScreen(
                              levels: tutorialLevels,
                              initialLevelIndex: i,
                            ),
                          ),
                        );
                        _refreshCompleted();
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TutorialCard extends StatelessWidget {
  final Level level;
  final bool completed;
  final VoidCallback onTap;

  const _TutorialCard({
    required this.level,
    required this.completed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: completed ? AppColors.success : AppColors.panelBorder),
        ),
        child: Row(
          children: [
            Icon(
              completed ? Icons.check_circle_rounded : Icons.school_rounded,
              color: completed ? AppColors.success : AppColors.accent,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                level.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
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
