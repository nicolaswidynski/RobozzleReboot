import 'package:flutter/material.dart';

import '../data/level_catalog.dart';
import '../data/progress_store.dart';
import '../models/level.dart';
import '../theme/app_colors.dart';
import 'game_screen.dart';

enum _SortBy { difficulty, popularity }

enum _DifficultyFilter {
  top30,
  level1,
  level2,
  level3,
  level4,
  level5,
  all;

  /// The specific difficulty rating this filter narrows to, or `null` for
  /// [top30]/[all] which span every difficulty.
  int? get level => switch (this) {
        level1 => 1,
        level2 => 2,
        level3 => 3,
        level4 => 4,
        level5 => 5,
        top30 || all => null,
      };
}

/// The app's default screen: every level, sortable by difficulty or
/// popularity. Tapping one opens [GameScreen] starting on that level.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final Future<List<Level>> _levelsFuture = _loadAllLevels();
  final ProgressStore _progressStore = ProgressStore();
  Set<String> _completedIds = const {};
  _SortBy _sortBy = _SortBy.difficulty;
  _DifficultyFilter _difficultyFilter = _DifficultyFilter.all;
  bool _hideCompleted = false;

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

  Future<List<Level>> _loadAllLevels() => loadCatalogLevels();

  List<MapEntry<int, Level>> _sortedLevels(List<Level> levels) {
    var indexed = [
      for (var i = 0; i < levels.length; i++) MapEntry(i, levels[i])
    ];

    if (_hideCompleted) {
      indexed =
          indexed.where((e) => !_completedIds.contains(e.value.id)).toList();
    }

    if (_sortBy == _SortBy.difficulty) {
      final level = _difficultyFilter.level;
      if (level != null) {
        indexed = indexed.where((e) => e.value.difficulty == level).toList();
      } else if (_difficultyFilter == _DifficultyFilter.top30) {
        final byDifficulty = <int, List<MapEntry<int, Level>>>{};
        for (final entry in indexed) {
          byDifficulty.putIfAbsent(entry.value.difficulty, () => []).add(entry);
        }
        indexed = [
          for (final group in byDifficulty.values)
            ...(group
                  ..sort((a, b) =>
                      b.value.popularity.compareTo(a.value.popularity)))
                .take(30),
        ];
      }
    }

    indexed.sort((a, b) {
      switch (_sortBy) {
        case _SortBy.difficulty:
          final byDifficulty = a.value.difficulty.compareTo(b.value.difficulty);
          return byDifficulty != 0
              ? byDifficulty
              : b.value.popularity.compareTo(a.value.popularity);
        case _SortBy.popularity:
          return b.value.popularity
              .compareTo(a.value.popularity); // most popular first
      }
    });
    return indexed;
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
              const Text(
                'Robozzle',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 28),
              ),
              const SizedBox(height: 4),
              Text(
                'Pick a puzzle',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6), fontSize: 14),
              ),
              const SizedBox(height: 18),
              Expanded(
                child: FutureBuilder<List<Level>>(
                  future: _levelsFuture,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          'Could not load levels: ${snapshot.error}',
                          style: const TextStyle(color: Colors.white70),
                          textAlign: TextAlign.center,
                        ),
                      );
                    }
                    final levels = snapshot.data;
                    if (levels == null) {
                      return const Center(
                        child:
                            CircularProgressIndicator(color: AppColors.accent),
                      );
                    }
                    final sorted = _sortedLevels(levels);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Sort by',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.6),
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(width: 10),
                            _SortChip(
                              label: 'Difficulty',
                              selected: _sortBy == _SortBy.difficulty,
                              onTap: () =>
                                  setState(() => _sortBy = _SortBy.difficulty),
                            ),
                            const SizedBox(width: 8),
                            _SortChip(
                              label: 'Popularity',
                              selected: _sortBy == _SortBy.popularity,
                              onTap: () =>
                                  setState(() => _sortBy = _SortBy.popularity),
                            ),
                            const Spacer(),
                            Text(
                              '${sorted.length} puzzles',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.4),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            _SortChip(
                              label: 'Hide completed',
                              selected: _hideCompleted,
                              onTap: () => setState(
                                  () => _hideCompleted = !_hideCompleted),
                            ),
                          ],
                        ),
                        if (_sortBy == _SortBy.difficulty) ...[
                          const SizedBox(height: 10),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                _SortChip(
                                  label: 'Top 30',
                                  selected: _difficultyFilter ==
                                      _DifficultyFilter.top30,
                                  onTap: () => setState(() =>
                                      _difficultyFilter =
                                          _DifficultyFilter.top30),
                                ),
                                for (final filter in const [
                                  _DifficultyFilter.level1,
                                  _DifficultyFilter.level2,
                                  _DifficultyFilter.level3,
                                  _DifficultyFilter.level4,
                                  _DifficultyFilter.level5,
                                ]) ...[
                                  const SizedBox(width: 8),
                                  _SortChip(
                                    label: '${filter.level}',
                                    selected: _difficultyFilter == filter,
                                    onTap: () => setState(
                                        () => _difficultyFilter = filter),
                                  ),
                                ],
                                const SizedBox(width: 8),
                                _SortChip(
                                  label: 'All',
                                  selected: _difficultyFilter ==
                                      _DifficultyFilter.all,
                                  onTap: () => setState(() =>
                                      _difficultyFilter =
                                          _DifficultyFilter.all),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        Expanded(
                          child: ListView.separated(
                            itemCount: sorted.length,
                            separatorBuilder: (context, index) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, i) {
                              final entry = sorted[i];
                              return _LevelCard(
                                level: entry.value,
                                completed:
                                    _completedIds.contains(entry.value.id),
                                onTap: () async {
                                  // Pass the list in the order currently
                                  // shown here (not the raw catalog order),
                                  // so GameScreen's Next button walks
                                  // through puzzles in this same sort/filter
                                  // order.
                                  await Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => GameScreen(
                                        levels:
                                            sorted.map((e) => e.value).toList(),
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

class _SortChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SortChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.accent : AppColors.panel,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? AppColors.accent : AppColors.panelBorder),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: Colors.white,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class _LevelCard extends StatelessWidget {
  final Level level;
  final bool completed;
  final VoidCallback onTap;

  const _LevelCard(
      {required this.level, required this.completed, required this.onTap});

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
            if (completed) ...[
              const Icon(Icons.check_circle_rounded,
                  color: AppColors.success, size: 20),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    level.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  if (level.author.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      'by ${level.author}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 11,
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.star_rounded,
                          color: AppColors.star, size: 14),
                      const SizedBox(width: 3),
                      Text(
                        '${level.totalStars}',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 12),
                      ),
                      const SizedBox(width: 14),
                      _DifficultyDots(difficulty: level.difficulty),
                      const SizedBox(width: 14),
                      Icon(
                        Icons.trending_up_rounded,
                        color: Colors.white.withValues(alpha: 0.4),
                        size: 14,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '${level.popularity}',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: Colors.white.withValues(alpha: 0.4)),
          ],
        ),
      ),
    );
  }
}

class _DifficultyDots extends StatelessWidget {
  static const int _maxDifficulty = 5;

  final int difficulty;

  const _DifficultyDots({required this.difficulty});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < _maxDifficulty; i++)
          Padding(
            padding: const EdgeInsets.only(right: 2),
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < difficulty
                    ? AppColors.accent
                    : Colors.white.withValues(alpha: 0.15),
              ),
            ),
          ),
      ],
    );
  }
}
