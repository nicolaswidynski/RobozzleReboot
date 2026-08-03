import 'package:flutter/material.dart';

import '../data/catalog_refresher.dart';
import '../data/level_catalog.dart';
import '../data/progress_store.dart';
import '../models/level.dart';
import '../theme/app_colors.dart';
import '../widgets/rating_prompt_dialog.dart';
import 'game_screen.dart';

enum _SortBy { difficulty, popularity }

enum _DifficultyFilter {
  level1,
  level2,
  level3,
  level4,
  level5,
  all;

  /// The specific difficulty rating this filter narrows to, or `null` for
  /// [all], which spans every difficulty.
  int? get level => switch (this) {
        level1 => 1,
        level2 => 2,
        level3 => 3,
        level4 => 4,
        level5 => 5,
        all => null,
      };
}

/// Browses the scraped Robozzle catalog: every level, sortable by
/// difficulty or popularity. Tapping one opens [GameScreen] starting on
/// that level.
///
/// Reused for both "Community Puzzles" (the full catalog, minus
/// [excludeAuthors]) and "Campaign" (the same catalog narrowed to just
/// [authorFilter]) — the two are meant to partition the catalog, not
/// overlap, so a puzzle by a Campaign author only ever shows up there.
class HomeScreen extends StatefulWidget {
  final String title;

  /// When set, only levels whose author (case-insensitively) is in this
  /// set are shown. `null` means no filtering — the full catalog (minus
  /// [excludeAuthors], if that's set instead).
  final Set<String>? authorFilter;

  /// When set, levels whose author (case-insensitively) is in this set are
  /// hidden — the opposite of [authorFilter]. Only one of the two is ever
  /// meaningfully set at once.
  final Set<String>? excludeAuthors;

  /// Whether the player can switch between sorting by difficulty and by
  /// popularity. When `false` (Campaign), sorting is fixed to difficulty
  /// and the Sort-by chips are hidden entirely.
  final bool allowSortChoice;

  const HomeScreen({
    super.key,
    this.title = 'Community Puzzles',
    this.authorFilter,
    this.excludeAuthors,
    this.allowSortChoice = true,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<Level>> _levelsFuture = _loadAllLevels();
  late final Set<String>? _authorFilter =
      widget.authorFilter?.map((a) => a.toLowerCase()).toSet();
  late final Set<String>? _excludeAuthors =
      widget.excludeAuthors?.map((a) => a.toLowerCase()).toSet();
  final ProgressStore _progressStore = ProgressStore();
  final TextEditingController _searchController = TextEditingController();
  Set<String> _completedIds = const {};
  _SortBy _sortBy = _SortBy.difficulty;
  _DifficultyFilter _difficultyFilter = _DifficultyFilter.all;
  bool _hideCompleted = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _refreshCompleted();
    _searchController.addListener(
      () => setState(() => _searchQuery = _searchController.text.trim()),
    );
    // No daily refresh trigger here — LandingScreen already does one on
    // every launch, and it shares CatalogRefresher's throttle/cache with
    // this screen, so by the time this opens there's nothing left to do
    // that a second one wouldn't just skip anyway.
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refreshCompleted() async {
    final ids = await _progressStore.loadCompleted();
    if (!mounted) return;
    setState(() => _completedIds = ids);
    maybeShowRatingPrompt(context, _completedIds.length);
  }

  /// Pull-to-refresh from the top of the list — always shows the loading
  /// spinner for the duration of the request, unlike the silent daily check.
  Future<void> _onPullToRefresh() =>
      _refreshCatalogMetadata(CatalogRefresher.instance.refreshNow());

  /// Reloads the level list (bundled catalog + any cached server overrides)
  /// only if [refreshed] actually fetched new metadata — never blocks or
  /// errors the UI, since browsing must keep working offline.
  Future<void> _refreshCatalogMetadata(Future<bool> refreshed) async {
    if (await refreshed && mounted) {
      setState(() => _levelsFuture = _loadAllLevels());
    }
  }

  Future<List<Level>> _loadAllLevels() => loadCatalogLevels();

  List<MapEntry<int, Level>> _sortedLevels(List<Level> levels) {
    var indexed = [
      for (var i = 0; i < levels.length; i++) MapEntry(i, levels[i])
    ];

    final authorFilter = _authorFilter;
    if (authorFilter != null) {
      indexed = indexed
          .where((e) => authorFilter.contains(e.value.author.toLowerCase()))
          .toList();
    }

    final excludeAuthors = _excludeAuthors;
    if (excludeAuthors != null) {
      indexed = indexed
          .where((e) => !excludeAuthors.contains(e.value.author.toLowerCase()))
          .toList();
    }

    if (_hideCompleted) {
      indexed =
          indexed.where((e) => !_completedIds.contains(e.value.id)).toList();
    }

    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      indexed = indexed
          .where((e) => e.value.name.toLowerCase().contains(query))
          .toList();
    }

    if (_sortBy == _SortBy.difficulty) {
      final level = _difficultyFilter.level;
      if (level != null) {
        indexed =
            indexed.where((e) => e.value.difficultyStars == level).toList();
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
                  Text(
                    widget.title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 26),
                  ),
                ],
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
                        TextField(
                          controller: _searchController,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 14),
                          decoration: InputDecoration(
                            hintText: 'Search by name',
                            hintStyle: TextStyle(
                              color: Colors.white.withValues(alpha: 0.4),
                            ),
                            prefixIcon: Icon(
                              Icons.search_rounded,
                              color: Colors.white.withValues(alpha: 0.4),
                            ),
                            suffixIcon: _searchQuery.isEmpty
                                ? null
                                : IconButton(
                                    icon: Icon(
                                      Icons.clear_rounded,
                                      color:
                                          Colors.white.withValues(alpha: 0.4),
                                    ),
                                    onPressed: _searchController.clear,
                                  ),
                            filled: true,
                            fillColor: AppColors.panel,
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 10),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(
                                  color: AppColors.panelBorder),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(
                                  color: AppColors.panelBorder),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide:
                                  const BorderSide(color: AppColors.accent),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            if (widget.allowSortChoice) ...[
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
                                onTap: () => setState(
                                    () => _sortBy = _SortBy.difficulty),
                              ),
                              const SizedBox(width: 8),
                              _SortChip(
                                label: 'Popularity',
                                selected: _sortBy == _SortBy.popularity,
                                onTap: () => setState(
                                    () => _sortBy = _SortBy.popularity),
                              ),
                            ],
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
                          // Wrap, not a horizontally-scrolling Row — see
                          // the same choice in ControlBar for why a
                          // scrollable flush against the left edge fights
                          // iOS's edge-swipe-back gesture.
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final filter in const [
                                _DifficultyFilter.level1,
                                _DifficultyFilter.level2,
                                _DifficultyFilter.level3,
                                _DifficultyFilter.level4,
                                _DifficultyFilter.level5,
                              ])
                                _SortChip(
                                  label: '${filter.level}',
                                  selected: _difficultyFilter == filter,
                                  onTap: () => setState(
                                      () => _difficultyFilter = filter),
                                ),
                              _SortChip(
                                label: 'All',
                                selected: _difficultyFilter ==
                                    _DifficultyFilter.all,
                                onTap: () => setState(() =>
                                    _difficultyFilter = _DifficultyFilter.all),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 16),
                        Expanded(
                          child: RefreshIndicator(
                            onRefresh: _onPullToRefresh,
                            color: AppColors.accent,
                            backgroundColor: AppColors.panel,
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
                                          levels: sorted
                                              .map((e) => e.value)
                                              .toList(),
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
                      _DifficultyDots(difficulty: level.difficultyStars),
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

/// Same star language as the post-solve difficulty rating and the editor's
/// "suggested difficulty" picker, for visual consistency across the app.
class _DifficultyDots extends StatelessWidget {
  static const int _maxDifficulty = 5;

  final int difficulty;

  const _DifficultyDots({required this.difficulty});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 1; i <= _maxDifficulty; i++)
          Icon(
            i <= difficulty ? Icons.star_rounded : Icons.star_border_rounded,
            color: AppColors.star,
            size: 13,
          ),
      ],
    );
  }
}
