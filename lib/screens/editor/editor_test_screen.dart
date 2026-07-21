import 'dart:async';

import 'package:flutter/material.dart';

import '../../engine/interpreter.dart';
import '../../models/instruction.dart';
import '../../models/level.dart';
import '../../models/program.dart';
import '../../models/tile_color.dart';
import '../../theme/app_colors.dart';
import '../../widgets/control_bar.dart';
import '../../widgets/function_editor.dart';
import '../../widgets/instruction_palette.dart';
import '../../widgets/robot_grid.dart';

/// Lets the puzzle author play their own draft [level] to prove it's
/// solvable — a stripped-down [GameScreen] with no level list/Next, no
/// ProgressStore/rating (this isn't a published puzzle yet). On success,
/// offers to accept the solve and pops with the winning [RobotProgram];
/// the caller (EditorScreen) is what actually persists it.
class EditorTestScreen extends StatefulWidget {
  final Level level;

  const EditorTestScreen({super.key, required this.level});

  @override
  State<EditorTestScreen> createState() => _EditorTestScreenState();
}

class _EditorTestScreenState extends State<EditorTestScreen> {
  late RobotProgram _program;
  late RobotInterpreter _interpreter;

  ActionType? _selectedAction;
  bool _eraserSelected = false;
  TileColor _selectedCondition = TileColor.any;
  bool _functionsVisible = true;

  Timer? _autoRunTimer;
  int? _runSpeed;

  bool _showSolvedOverlay = false;

  static const Duration _baseStepInterval = Duration(milliseconds: 260);
  static const Duration _stepAnimationDuration = Duration(milliseconds: 180);

  static const List<ActionType> _baseActions = [
    ActionType.forward,
    ActionType.turnLeft,
    ActionType.turnRight,
    ActionType.paintRed,
    ActionType.paintGreen,
    ActionType.paintBlue,
  ];

  Level get _level => widget.level;

  @override
  void initState() {
    super.initState();
    _program = RobotProgram.empty(_level);
    _interpreter = RobotInterpreter(level: _level, program: _program);
    _selectedAction = ActionType.forward;
  }

  @override
  void dispose() {
    _autoRunTimer?.cancel();
    super.dispose();
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
      return;
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
      _interpreter = RobotInterpreter(level: _level, program: _program);
      _showSolvedOverlay = false;
    });
  }

  void _onSlotDrop(
      int functionIndex, int slotIndex, ProgramInstruction instruction) {
    if (_interpreter.status == RunStatus.running && _autoRunTimer != null) {
      return;
    }
    setState(() {
      _program.setSlot(functionIndex, slotIndex, instruction);
      _interpreter = RobotInterpreter(level: _level, program: _program);
      _showSolvedOverlay = false;
    });
  }

  void _onSlotConditionDrop(int functionIndex, int slotIndex, TileColor color) {
    if (_interpreter.status == RunStatus.running && _autoRunTimer != null) {
      return;
    }
    final existing = _program.functions[functionIndex].slots[slotIndex];
    if (existing == null) return;
    setState(() {
      _program.setSlot(
          functionIndex, slotIndex, existing.copyWith(condition: color));
      _interpreter = RobotInterpreter(level: _level, program: _program);
      _showSolvedOverlay = false;
    });
  }

  void _onSlotMove(
      int toFunctionIndex, int toSlotIndex, SlotInstructionMove move) {
    if (_interpreter.status == RunStatus.running && _autoRunTimer != null) {
      return;
    }
    setState(() {
      _program.setSlot(move.functionIndex, move.slotIndex, null);
      _program.setSlot(toFunctionIndex, toSlotIndex, move.instruction);
      _interpreter = RobotInterpreter(level: _level, program: _program);
      _showSolvedOverlay = false;
    });
  }

  void _onSlotRemove(int functionIndex, int slotIndex) {
    if (_interpreter.status == RunStatus.running && _autoRunTimer != null) {
      return;
    }
    setState(() {
      _program.setSlot(functionIndex, slotIndex, null);
      _interpreter = RobotInterpreter(level: _level, program: _program);
      _showSolvedOverlay = false;
    });
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
    _maybeShowSolved();
  }

  void _maybeShowSolved() {
    if (_interpreter.status == RunStatus.success && !_showSolvedOverlay) {
      setState(() => _showSolvedOverlay = true);
    }
  }

  void _stepBack() {
    if (_autoRunTimer != null) return;
    setState(() {
      _interpreter.stepBack();
      _showSolvedOverlay = false;
    });
  }

  void _setRunSpeed(int multiplier) {
    if (_runSpeed == multiplier) {
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
      _maybeShowSolved();
    });
    setState(() => _runSpeed = multiplier);
  }

  void _reset() {
    setState(() {
      _autoRunTimer?.cancel();
      _autoRunTimer = null;
      _runSpeed = null;
      _interpreter.reset();
      _showSolvedOverlay = false;
    });
  }

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
                  _TestHeader(title: _level.name),
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
          if (_showSolvedOverlay)
            Positioned.fill(
              child: _SolvedOverlay(
                onSave: () => Navigator.of(context).pop(_program),
                onKeepTesting: () => setState(() => _showSolvedOverlay = false),
              ),
            ),
        ],
      ),
    );
  }
}

class _TestHeader extends StatelessWidget {
  final String title;

  const _TestHeader({required this.title});

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
          Builder(
            builder: (context) => InkWell(
              onTap: () => Navigator.of(context).pop(),
              customBorder: const CircleBorder(),
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(Icons.close_rounded, color: Colors.white70, size: 24),
              ),
            ),
          ),
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
          const SizedBox(width: 36), // balances the close button
        ],
      ),
    );
  }
}

/// An invisible swipe strip above the function panels, mirroring
/// GameScreen's — swipe up/down (or tap) to show/hide all functions.
class _FunctionsHandle extends StatelessWidget {
  final bool visible;
  final VoidCallback onToggle;

  const _FunctionsHandle({required this.visible, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onToggle,
      onVerticalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity < -150 && !visible) {
          onToggle();
        } else if (velocity > 150 && visible) {
          onToggle();
        }
      },
      child: const SizedBox(width: double.infinity, height: 24),
    );
  }
}

class _SolvedOverlay extends StatelessWidget {
  final VoidCallback onSave;
  final VoidCallback onKeepTesting;

  const _SolvedOverlay({required this.onSave, required this.onKeepTesting});

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
              'Solved!',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 24),
            ),
            const SizedBox(height: 8),
            Text(
              'Your puzzle is provably solvable. Save it?',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onSave,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text(
                  'Save Puzzle',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: onKeepTesting,
                child: Text(
                  'Keep Testing',
                  style:
                      TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
