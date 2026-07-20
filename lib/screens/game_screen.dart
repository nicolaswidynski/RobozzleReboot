import 'dart:async';

import 'package:flutter/material.dart';

import '../data/program_store.dart';
import '../data/progress_store.dart';
import '../engine/interpreter.dart';
import '../models/instruction.dart';
import '../models/level.dart';
import '../models/program.dart';
import '../models/tile_color.dart';
import '../theme/app_colors.dart';
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

  ActionType? _selectedAction;
  bool _eraserSelected = false;
  TileColor _selectedCondition = TileColor.any;
  bool _functionsVisible = true;

  Timer? _autoRunTimer;
  int? _runSpeed; // null = paused, otherwise 1, 2, or 8

  // The Clear overlay is shown on a short delay after success rather than
  // instantly, so it doesn't pop up while the robot's move/turn animation
  // (see RobotGrid) is still visibly catching up to the winning tile.
  Timer? _clearOverlayTimer;
  bool _showClearOverlay = false;
  static const Duration _clearOverlayDelay = Duration(milliseconds: 220);

  final ProgressStore _progressStore = ProgressStore();
  final ProgramStore _programStore = ProgramStore();

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
    _loadLevel(widget.initialLevelIndex);
  }

  @override
  void dispose() {
    _autoRunTimer?.cancel();
    _clearOverlayTimer?.cancel();
    super.dispose();
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
    _selectedAction = ActionType.forward;
    _eraserSelected = false;
    _selectedCondition = TileColor.any;
    _functionsVisible = true;
    _restoreSavedProgram();
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

  void _onSlotTap(int functionIndex, int slotIndex) {
    if (_interpreter.status == RunStatus.running && _autoRunTimer != null) {
      return; // don't allow edits mid auto-run
    }
    setState(() {
      if (_eraserSelected) {
        _program.setSlot(functionIndex, slotIndex, null);
      } else if (_selectedAction != null) {
        _program.setSlot(
          functionIndex,
          slotIndex,
          ProgramInstruction(_selectedAction!, condition: _selectedCondition),
        );
      }
      // Editing the program after a run has started invalidates progress —
      // rebuild a fresh interpreter against the edited program.
      _interpreter = RobotInterpreter(level: _level, program: _program);
      _resetClearOverlay();
    });
    _programStore.save(_level, _program);
  }

  void _onSlotDrop(
      int functionIndex, int slotIndex, ProgramInstruction instruction) {
    if (_interpreter.status == RunStatus.running && _autoRunTimer != null) {
      return; // don't allow edits mid auto-run
    }
    setState(() {
      _program.setSlot(functionIndex, slotIndex, instruction);
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
    setState(() {
      _program.setSlot(move.functionIndex, move.slotIndex, null);
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
  // when the player tapped in — so stepping through it follows that order.
  VoidCallback? get _goToNextLevel => _levelIndex < _levels.length - 1
      ? () => setState(() => _loadLevel(_levelIndex + 1))
      : null;

  @override
  Widget build(BuildContext context) {
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
                          onStep: _step,
                          onStepBack: _stepBack,
                          onSetSpeed: _setRunSpeed,
                          onReset: _reset,
                        ),
                        const SizedBox(height: 10),
                        _FunctionsHandle(
                          visible: _functionsVisible,
                          onToggle: () => setState(
                              () => _functionsVisible = !_functionsVisible),
                        ),
                        const SizedBox(height: 4),
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
                                            onSlotTap: (slot) =>
                                                _onSlotTap(i, slot),
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
                        const SizedBox(height: 8),
                        InstructionPalette(
                          availableActions: _availableActions,
                          selectedAction: _selectedAction,
                          eraserSelected: _eraserSelected,
                          selectedCondition: _selectedCondition,
                          enabled: _autoRunTimer == null,
                          onActionSelected: (a) => setState(() {
                            _selectedAction = a;
                            _eraserSelected = false;
                          }),
                          onEraserSelected: () =>
                              setState(() => _eraserSelected = true),
                          onConditionSelected: (c) =>
                              setState(() => _selectedCondition = c),
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
              child: _ClearOverlay(onNext: _goToNextLevel),
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

  const _Header(
      {required this.title, required this.onHome, required this.onNext});

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
      child: const SizedBox(width: double.infinity, height: 24),
    );
  }
}

/// Shown full-screen over the puzzle once it's solved (all stars collected,
/// robot at the end). [onNext] advances through [GameScreen.levels] in
/// whatever order HomeScreen passed them in — i.e. the sort/filter that was
/// active there when the player tapped in.
class _ClearOverlay extends StatelessWidget {
  final VoidCallback? onNext;

  const _ClearOverlay({required this.onNext});

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
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onNext,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  disabledBackgroundColor: Colors.white.withValues(alpha: 0.08),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                  onNext == null ? 'Last puzzle' : 'Next',
                  style: TextStyle(
                    color: onNext == null ? Colors.white38 : Colors.white,
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
