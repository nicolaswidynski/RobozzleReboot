import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/points.dart';
import '../data/program_store.dart';
import '../data/progress_store.dart';
import '../data/puzzle_content.dart';
import '../data/puzzle_rating_store.dart';
import '../data/robozzle_api_client.dart';
import '../engine/interpreter.dart';
import '../models/instruction.dart';
import '../models/level.dart';
import '../models/program.dart';
import '../models/tile_color.dart';
import '../theme/app_colors.dart';
import '../utils/shake_detector.dart';
import '../widgets/control_bar.dart';
import '../widgets/function_editor.dart';
import '../widgets/instruction_palette.dart';
import '../widgets/robot_grid.dart';

class GameScreen extends StatefulWidget {
  final List<Level> levels;
  final int initialLevelIndex;

  const GameScreen(
      {super.key, required this.levels, this.initialLevelIndex = 0});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late final List<Level> _levels = widget.levels;
  int _levelIndex = 0;

  late Level _level;
  late RobotProgram _program;
  late RobotInterpreter _interpreter;

  // Puzzles the server only listed (never bundled, and not fetched before)
  // start with an empty grid — fetched on demand right before they're
  // opened. These track that fetch so build() can show a loading/error
  // state instead of touching the not-yet-initialized fields above.
  bool _loadingLevel = false;
  String? _levelLoadError;
  int _pendingLevelIndex = 0;

  bool _functionsVisible = true;

  Timer? _autoRunTimer;
  int? _runSpeed; // null = paused, otherwise 1, 2, or 8

  // The Clear overlay is shown on a short delay after success rather than
  // instantly, so it doesn't pop up while the robot's move/turn animation
  // (see RobotGrid) is still visibly catching up to the winning tile.
  Timer? _clearOverlayTimer;
  bool _showClearOverlay = false;
  static const Duration _clearOverlayDelay = Duration(milliseconds: 220);

  // Rate/like prompt shown on the Clear overlay. `_ratingHandled` covers
  // both "already rated in an earlier session" (loaded from
  // PuzzleRatingStore) and "just submitted this session" — either way, the
  // prompt hides and won't submit again for this puzzle.
  int? _selectedRating;
  bool _liked = false;
  bool _ratingHandled = false;

  final ProgressStore _progressStore = ProgressStore();
  final ProgramStore _programStore = ProgramStore();

  // Loaded once on open (from a previous session, or synced in via the
  // account-wide completed-puzzles list) and kept up to date as puzzles
  // are solved this session — lets _goToNextLevel skip levels there's
  // nothing left to do on, rather than making the player click through
  // them one by one.
  Set<String> _completedIds = {};

  // Shaking the device while a level is loaded prompts to clear the whole
  // program — a fast way to start a puzzle over without hunting down every
  // placed instruction individually. `_shakeConfirmOpen` guards against a
  // second shake mid-gesture reopening the confirm dialog on top of itself.
  late final ShakeDetector _shakeDetector =
      ShakeDetector(onShake: _onShakeDetected);
  bool _shakeConfirmOpen = false;

  static const Duration _baseStepInterval = Duration(milliseconds: 260);
  static const Duration _maxStepAnimationDuration = Duration(milliseconds: 180);

  // The robot's move/turn animation must never take longer than the actual
  // gap between steps — otherwise, at high auto-run speeds, each new step
  // retargets the animation before it finishes the previous tile and it
  // visually never catches up (looks like skipped tiles, even though every
  // step still executes correctly underneath).
  Duration get _stepAnimationDuration {
    if (_runSpeed == null) return _maxStepAnimationDuration;
    final interval = Duration(
      milliseconds: (_baseStepInterval.inMilliseconds / _runSpeed!).round(),
    );
    return interval < _maxStepAnimationDuration
        ? interval
        : _maxStepAnimationDuration;
  }

  static const List<ActionType> _baseActions = [
    ActionType.forward,
    ActionType.turnLeft,
    ActionType.turnRight,
    ActionType.paintRed,
    ActionType.paintGreen,
    ActionType.paintBlue,
  ];

  @override
  void initState() {
    super.initState();
    _prepareAndLoadLevel(widget.initialLevelIndex);
    _shakeDetector.start();
    _loadCompletedIds();
  }

  Future<void> _loadCompletedIds() async {
    final ids = await _progressStore.loadCompleted();
    if (!mounted) return;
    setState(() => _completedIds = ids);
  }

  @override
  void dispose() {
    _autoRunTimer?.cancel();
    _clearOverlayTimer?.cancel();
    _shakeDetector.stop();
    super.dispose();
  }

  // Ignored while a level is still loading, mid auto-run (same guard as
  // every other edit), a confirm dialog is already up, or the program is
  // already empty (nothing to clear).
  void _onShakeDetected() {
    if (_loadingLevel || _levelLoadError != null) return;
    if (_autoRunTimer != null) return;
    if (_shakeConfirmOpen) return;
    if (!_program.functions.any((fn) => fn.slots.any((s) => s != null))) {
      return;
    }
    _shakeConfirmOpen = true;
    HapticFeedback.mediumImpact();
    showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.panel,
        title: const Text('Clear all instructions?',
            style: TextStyle(color: Colors.white)),
        content: Text(
          'This removes every instruction from every function. It can\'t be undone.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    ).then((confirmed) {
      _shakeConfirmOpen = false;
      if (confirmed == true) _clearProgram();
    });
  }

  void _clearProgram() {
    setState(() {
      _program.clearAll();
      _interpreter = RobotInterpreter(level: _level, program: _program);
      _resetClearOverlay();
    });
    _programStore.save(_level, _program);
  }

  /// Ensures `_levels[index]` has its playable content (fetching it from
  /// `robozzle-get-puzzle` if this is a server-only puzzle never opened
  /// before — see [ensurePuzzleContent]) before actually loading it. A
  /// no-op fetch for every bundled puzzle, which already has content.
  Future<void> _prepareAndLoadLevel(int index) async {
    _pendingLevelIndex = index;
    var level = _levels[index];
    if (level.grid.isEmpty) {
      setState(() {
        _loadingLevel = true;
        _levelLoadError = null;
      });
      try {
        level = await ensurePuzzleContent(level);
        _levels[index] = level;
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _loadingLevel = false;
          _levelLoadError = '$e';
        });
        return;
      }
    }
    if (!mounted) return;
    setState(() {
      _loadingLevel = false;
      _levelLoadError = null;
      _loadLevel(index);
    });
    _maybeShowInstructions();
  }

  /// Shows [_level.description] (if it has one — only the hand-authored
  /// tutorial levels do) once the frame with the new level has actually
  /// built, since showDialog needs an Overlay already in the tree.
  void _maybeShowInstructions() {
    if (_level.description.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showInstructionsDialog();
    });
  }

  void _showInstructionsDialog() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.panel,
        title: Text(_level.name, style: const TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Text(
            _level.description,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.8), height: 1.4),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  void _loadLevel(int index) {
    _autoRunTimer?.cancel();
    _autoRunTimer = null;
    _runSpeed = null;
    _resetClearOverlay();
    _level = _levels[index];
    _levelIndex = index;
    _program = RobotProgram.empty(_level);
    _interpreter = RobotInterpreter(level: _level, program: _program);
    _functionsVisible = true;
    _selectedRating = null;
    _liked = false;
    _ratingHandled = false;
    _restoreSavedProgram();
    _loadRatingStatus();
  }

  // Loads asynchronously since it's a SharedPreferences ProgramStore. If
  // the player has already put something into this level, drop their saved
  // program in instead of leaving them with a blank slate.
  Future<void> _restoreSavedProgram() async {
    final level = _level;
    final saved = await _programStore.load(level);
    if (saved == null) return;
    if (!mounted || _level != level) return; // stale: level changed meanwhile
    setState(() {
      _program = saved;
      _interpreter = RobotInterpreter(level: _level, program: _program);
    });
  }

  // Loads asynchronously since it's a SharedPreferences PuzzleRatingStore.
  // If this puzzle was already rated in an earlier session, the rate/like
  // prompt on the Clear overlay should stay hidden.
  Future<void> _loadRatingStatus() async {
    final level = _level;
    final rated = (await PuzzleRatingStore().loadRated()).contains(level.id);
    if (!rated) return;
    if (!mounted || _level != level) return; // stale: level changed meanwhile
    setState(() => _ratingHandled = true);
  }

  void _resetClearOverlay() {
    _clearOverlayTimer?.cancel();
    _clearOverlayTimer = null;
    _showClearOverlay = false;
  }

  static const Map<ActionType, TileColor> _paintColorOf = {
    ActionType.paintRed: TileColor.red,
    ActionType.paintGreen: TileColor.green,
    ActionType.paintBlue: TileColor.blue,
  };

  List<ActionType> get _availableActions {
    final calls = <ActionType>[
      ActionType.callF1,
      ActionType.callF2,
      ActionType.callF3,
      ActionType.callF4,
      ActionType.callF5,
    ];
    return [
      for (final action in _baseActions)
        if (!_paintColorOf.containsKey(action) ||
            _level.allowedPaintColors.contains(_paintColorOf[action]))
          action,
      for (var i = 0; i < 5; i++)
        if (_level.slotsPerFunction[i] > 0) calls[i],
    ];
  }

  void _onSlotDrop(
      int functionIndex, int slotIndex, ProgramInstruction instruction) {
    if (_interpreter.status == RunStatus.running && _autoRunTimer != null) {
      return; // don't allow edits mid auto-run
    }
    // Dropping a fresh instruction from the palette onto a slot that
    // already holds one keeps that slot's condition color instead of
    // wiping it back to "no color" — only the action changes.
    final existing = _program.functions[functionIndex].slots[slotIndex];
    final toPlace = existing != null && existing.condition != TileColor.any
        ? instruction.copyWith(condition: existing.condition)
        : instruction;
    setState(() {
      _program.setSlot(functionIndex, slotIndex, toPlace);
      _interpreter = RobotInterpreter(level: _level, program: _program);
      _resetClearOverlay();
    });
    _programStore.save(_level, _program);
  }

  void _onSlotConditionDrop(int functionIndex, int slotIndex, TileColor color) {
    if (_interpreter.status == RunStatus.running && _autoRunTimer != null) {
      return; // don't allow edits mid auto-run
    }
    final existing = _program.functions[functionIndex].slots[slotIndex];
    if (existing == null) return;
    setState(() {
      _program.setSlot(
          functionIndex, slotIndex, existing.copyWith(condition: color));
      _interpreter = RobotInterpreter(level: _level, program: _program);
      _resetClearOverlay();
    });
    _programStore.save(_level, _program);
  }

  void _onSlotMove(
      int toFunctionIndex, int toSlotIndex, SlotInstructionMove move) {
    if (_interpreter.status == RunStatus.running && _autoRunTimer != null) {
      return; // don't allow edits mid auto-run
    }
    if (toFunctionIndex == move.functionIndex &&
        toSlotIndex == move.slotIndex) {
      return; // dropped back onto itself
    }
    setState(() {
      // Dropping onto an already-filled slot swaps the two instructions
      // instead of the destination's one silently disappearing.
      final displaced =
          _program.functions[toFunctionIndex].slots[toSlotIndex];
      _program.setSlot(move.functionIndex, move.slotIndex, displaced);
      _program.setSlot(toFunctionIndex, toSlotIndex, move.instruction);
      _interpreter = RobotInterpreter(level: _level, program: _program);
      _resetClearOverlay();
    });
    _programStore.save(_level, _program);
  }

  void _onSlotRemove(int functionIndex, int slotIndex) {
    if (_interpreter.status == RunStatus.running && _autoRunTimer != null) {
      return; // don't allow edits mid auto-run
    }
    setState(() {
      _program.setSlot(functionIndex, slotIndex, null);
      _interpreter = RobotInterpreter(level: _level, program: _program);
      _resetClearOverlay();
    });
    _programStore.save(_level, _program);
  }

  void _autoExpandRunning() {
    if (_interpreter.highlightFunction != null) {
      _functionsVisible = true;
    }
  }

  void _step() {
    setState(() {
      _interpreter.step();
      _autoExpandRunning();
      if (_interpreter.status.isTerminal) {
        _autoRunTimer?.cancel();
        _autoRunTimer = null;
        _runSpeed = null;
      }
    });
    _maybeMarkCompleted();
  }

  void _maybeMarkCompleted() {
    if (_interpreter.status == RunStatus.success) {
      _progressStore.markCompleted(_level.id);
      // Records this attempt's efficiency (see points.dart) as the
      // level's best-ever if it beats whatever's already stored — the
      // `par` figure reported to the leaderboard, and the source for the
      // Clear overlay's bonus-points display below.
      _progressStore.recordPar(_level.id, unusedSlots(_program));
      // So _goToNextLevel already knows to skip this one — no need to wait
      // on the store round-trip, and no setState needed here either: the
      // Clear overlay (which is what actually reads _goToNextLevel) only
      // appears after the setState below fires.
      _completedIds.add(_level.id);
      // Redundant with the save already done on every edit, but cheap and
      // guarantees the exact winning program is what's persisted.
      _programStore.save(_level, _program);
      if (!_showClearOverlay && _clearOverlayTimer == null) {
        _clearOverlayTimer = Timer(_clearOverlayDelay, () {
          _clearOverlayTimer = null;
          if (!mounted) return;
          setState(() => _showClearOverlay = true);
        });
      }
    }
  }

  void _stepBack() {
    // Pause first — mid-run rewinding isn't supported.
    if (_autoRunTimer != null) {
      return;
    }
    setState(() {
      _interpreter.stepBack();
      _resetClearOverlay();
    });
  }

  void _setRunSpeed(int multiplier) {
    if (_runSpeed == multiplier) {
      // Tapping the currently-active speed pauses.
      setState(() {
        _autoRunTimer?.cancel();
        _autoRunTimer = null;
        _runSpeed = null;
      });
      return;
    }
    _autoRunTimer?.cancel();
    final interval = Duration(
      milliseconds: (_baseStepInterval.inMilliseconds / multiplier).round(),
    );
    _autoRunTimer = Timer.periodic(interval, (_) {
      if (!mounted) return;
      setState(() {
        _interpreter.step();
        _autoExpandRunning();
        if (_interpreter.status.isTerminal) {
          _autoRunTimer?.cancel();
          _autoRunTimer = null;
          _runSpeed = null;
        }
      });
      _maybeMarkCompleted();
    });
    setState(() => _runSpeed = multiplier);
  }

  void _reset() {
    setState(() {
      _autoRunTimer?.cancel();
      _autoRunTimer = null;
      _runSpeed = null;
      _interpreter.reset();
      _resetClearOverlay();
    });
  }

  // _levels is exactly the list HomeScreen handed us — already in whatever
  // sort/filter order (difficulty/popularity, Top 30/All) was active there
  // when the player tapped in — so stepping through it follows that order,
  // skipping past any level already solved (this session, a previous one,
  // or synced in from another device) rather than making the player click
  // through puzzles there's nothing left to do on.
  int? get _nextIncompleteLevelIndex {
    for (var i = _levelIndex + 1; i < _levels.length; i++) {
      if (!_completedIds.contains(_levels[i].id)) return i;
    }
    return null;
  }

  VoidCallback? get _goToNextLevel =>
      _nextIncompleteLevelIndex != null ? () => _advanceToNextLevel() : null;

  Future<void> _advanceToNextLevel() async {
    _submitRatingIfNeeded();
    final nextIndex = _nextIncompleteLevelIndex;
    if (nextIndex == null) return;
    await _prepareAndLoadLevel(nextIndex);
  }

  // Reached when the Clear overlay's button has no next puzzle to advance
  // to — still submits any pending rating, then returns to the list (e.g.
  // to pick a different difficulty) instead of leaving the button inert.
  void _backToList() {
    _submitRatingIfNeeded();
    Navigator.of(context).pop();
  }

  // Submits whatever rate/like the player picked (either can be unset) only
  // once, right when they click Next — never on every star/like tap, and
  // never again once a puzzle has been rated. Fires without waiting for the
  // network so it never delays advancing to the next puzzle; a failure just
  // means this puzzle isn't marked rated, so it's offered again next time.
  // Doesn't require being signed in — RobozzleApiClient.ratePuzzle sends
  // the signed-in identity when there is one, and rates anonymously
  // otherwise.
  void _submitRatingIfNeeded() {
    if (!_showClearOverlay || _ratingHandled) return;
    _ratingHandled = true;
    final level = _level;
    final puzzleId = level.id.replaceFirst('catalog-', '');
    final rate = _selectedRating?.toString() ?? '';
    final like = _liked ? 'yes' : '';
    RobozzleApiClient.instance
        .ratePuzzle(puzzleId: puzzleId, rate: rate, like: like)
        .then((_) => PuzzleRatingStore().markRated(level.id))
        .catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingLevel) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.accent),
        ),
      );
    }
    final error = _levelLoadError;
    if (error != null) {
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
                  'Could not load this puzzle.\n$error',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => _prepareAndLoadLevel(_pendingLevelIndex),
                  style:
                      ElevatedButton.styleFrom(backgroundColor: AppColors.accent),
                  child: const Text('Retry', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Column(
                children: [
                  _Header(
                    title: _level.name,
                    onHome: () => Navigator.of(context).pop(),
                    onNext: _goToNextLevel,
                    onHelp: _level.description.isEmpty
                        ? null
                        : _showInstructionsDialog,
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    flex: 4,
                    child: RobotGrid(
                      interpreter: _interpreter,
                      stepDuration: _stepAnimationDuration,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    flex: 6,
                    child: Column(
                      children: [
                        ControlBar(
                          status: _interpreter.status,
                          runSpeed: _runSpeed,
                          canStepBack: _interpreter.canStepBack,
                          starsRemaining: _interpreter.starsRemaining,
                          totalStars: _level.totalStars,
                          pendingByFrame: _interpreter.pendingByFrame,
                          onStep: _step,
                          onStepBack: _stepBack,
                          onSetSpeed: _setRunSpeed,
                          onReset: _reset,
                        ),
                        const SizedBox(height: 4),
                        _FunctionsHandle(
                          visible: _functionsVisible,
                          onToggle: () => setState(
                              () => _functionsVisible = !_functionsVisible),
                        ),
                        const SizedBox(height: 2),
                        // Only the function panels scroll — ControlBar above
                        // and InstructionPalette below stay fully visible,
                        // since some puzzles use all 5 functions and won't
                        // fit in the space left over otherwise. Flexible
                        // (not Expanded) so this area shrinks to fit when
                        // functions are hidden or few, instead of always
                        // claiming the full remaining height as blank space.
                        Flexible(
                          child: SingleChildScrollView(
                            child: AnimatedCrossFade(
                              duration: const Duration(milliseconds: 220),
                              crossFadeState: _functionsVisible
                                  ? CrossFadeState.showFirst
                                  : CrossFadeState.showSecond,
                              firstChild: IgnorePointer(
                                ignoring: _autoRunTimer != null,
                                child: AnimatedOpacity(
                                  opacity: _autoRunTimer != null ? 0.4 : 1,
                                  duration: const Duration(milliseconds: 180),
                                  child: Column(
                                    children: [
                                      for (var i = 0; i < 5; i++)
                                        if (_level.slotsPerFunction[i] > 0)
                                          FunctionPanel(
                                            label: 'F${i + 1}',
                                            functionIndex: i,
                                            function: _program.functions[i],
                                            highlightSlot: _interpreter
                                                        .highlightFunction ==
                                                    i
                                                ? _interpreter.highlightSlot
                                                : null,
                                            onSlotDrop: (slot, instr) =>
                                                _onSlotDrop(i, slot, instr),
                                            onConditionDrop: (slot, color) =>
                                                _onSlotConditionDrop(
                                                    i, slot, color),
                                            onSlotMove: (slot, move) =>
                                                _onSlotMove(i, slot, move),
                                            onSlotRemove: (slot) =>
                                                _onSlotRemove(i, slot),
                                          ),
                                    ],
                                  ),
                                ),
                              ),
                              secondChild: const SizedBox(
                                  width: double.infinity, height: 0),
                            ),
                          ),
                        ),
                        // No extra gap here — each FunctionPanel (including
                        // the last one) already carries its own 8px bottom
                        // margin, so adding another one on top of that
                        // doubled the visual gap before the palette.
                        InstructionPalette(
                          availableActions: _availableActions,
                          enabled: _autoRunTimer == null,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_showClearOverlay)
            Positioned.fill(
              child: _ClearOverlay(
                points: pointsForDifficulty(_level).round(),
                bonusPoints: bonusPoints(unusedSlots(_program), _level),
                onNext: _goToNextLevel,
                onBackToList: _backToList,
                showRating: !_ratingHandled,
                selectedRating: _selectedRating,
                onRateSelected: (rating) =>
                    setState(() => _selectedRating = rating),
                liked: _liked,
                onLikeToggle: () => setState(() => _liked = !_liked),
              ),
            ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String title;
  final VoidCallback onHome;
  final VoidCallback? onNext;
  final VoidCallback? onHelp;

  const _Header({
    required this.title,
    required this.onHome,
    required this.onNext,
    this.onHelp,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.panelBorder),
      ),
      child: Row(
        children: [
          _HeaderIconButton(icon: Icons.home_rounded, onTap: onHome),
          if (onHelp != null)
            _HeaderIconButton(icon: Icons.info_outline_rounded, onTap: onHelp),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
          ),
          _HeaderIconButton(icon: Icons.chevron_right_rounded, onTap: onNext),
        ],
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _HeaderIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon,
            color: disabled ? Colors.white24 : Colors.white70, size: 26),
      ),
    );
  }
}

/// An invisible swipe strip above the function panels. Swipe up to reveal
/// all functions, swipe down to hide them again (a tap also toggles, as a
/// fallback). This only ever shows/hides its own content — it never changes
/// the size of the grid above it.
class _FunctionsHandle extends StatelessWidget {
  final bool visible;
  final VoidCallback onToggle;

  const _FunctionsHandle({required this.visible, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const Key('functions_handle'),
      behavior: HitTestBehavior.opaque,
      onTap: onToggle,
      onVerticalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity < -150 && !visible) {
          onToggle(); // swiped up: show
        } else if (velocity > 150 && visible) {
          onToggle(); // swiped down: hide
        }
      },
      child: const SizedBox(width: double.infinity, height: 16),
    );
  }
}

/// Shown full-screen over the puzzle once it's solved (all stars collected,
/// robot at the end). [onNext] advances through [GameScreen.levels] in
/// whatever order HomeScreen passed them in — i.e. the sort/filter that was
/// active there when the player tapped in.
///
/// When [showRating] is true (this puzzle hasn't been rated before — no
/// sign-in required), also offers a one-time difficulty rating + like
/// prompt — picked here, but only actually submitted when the player taps
/// Next.
///
/// [onNext] is null once there's no next puzzle left in the list HomeScreen
/// handed us — the button stays enabled either way, falling back to
/// [onBackToList] (e.g. to pick a different difficulty) instead of being
/// disabled.
class _ClearOverlay extends StatelessWidget {
  final int points;
  final int bonusPoints;
  final VoidCallback? onNext;
  final VoidCallback onBackToList;
  final bool showRating;
  final int? selectedRating;
  final ValueChanged<int> onRateSelected;
  final bool liked;
  final VoidCallback onLikeToggle;

  const _ClearOverlay({
    required this.points,
    required this.bonusPoints,
    required this.onNext,
    required this.onBackToList,
    required this.showRating,
    required this.selectedRating,
    required this.onRateSelected,
    required this.liked,
    required this.onLikeToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.6),
      alignment: Alignment.center,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 32),
        padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.success, width: 1.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_rounded,
                color: AppColors.success, size: 56),
            const SizedBox(height: 14),
            const Text(
              'Clear!',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 24),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.star_rounded,
                    color: AppColors.star, size: 18),
                const SizedBox(width: 4),
                Text(
                  '+$points points',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
            // Only shown when the winning program left slots unused (see
            // points.dart's unusedSlots/bonusPoints) — a puzzle solved
            // using every available slot earns no bonus.
            if (bonusPoints > 0) ...[
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.bolt_rounded,
                      color: AppColors.accent, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    '+$bonusPoints bonus points',
                    style: const TextStyle(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ],
            if (showRating) ...[
              const SizedBox(height: 20),
              Text(
                'Rate the difficulty of this puzzle',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 1; i <= 5; i++)
                    InkWell(
                      onTap: () => onRateSelected(i),
                      customBorder: const CircleBorder(),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          (selectedRating ?? 0) >= i
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          color: AppColors.star,
                          size: 28,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              InkWell(
                onTap: onLikeToggle,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: liked ? AppColors.accent : AppColors.panel,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: liked ? AppColors.accent : AppColors.panelBorder,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        liked
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        liked ? 'Liked' : 'Like',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onNext ?? onBackToList,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                  onNext == null ? 'Go Back' : 'Next',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
