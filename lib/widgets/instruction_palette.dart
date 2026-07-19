import 'package:flutter/material.dart';

import '../models/instruction.dart';
import '../models/tile_color.dart';
import '../theme/app_colors.dart';
import 'action_glyph.dart';
import 'tile_color_ui.dart';

/// The bottom toolbox: pick an action (or the eraser), pick a color
/// condition, then either tap a slot in a [FunctionPanel] to place it, or
/// long-press an instruction here and drag it onto a slot directly.
///
/// `null` for the selected action means "eraser" — tapping a slot clears it
/// instead of placing an instruction.
///
/// Frozen (dimmed and unresponsive) via [enabled] while the program is
/// auto-running, since edits mid-run don't apply until you stop anyway.
class InstructionPalette extends StatelessWidget {
  final List<ActionType> availableActions;
  final ActionType? selectedAction;
  final bool eraserSelected;
  final TileColor selectedCondition;
  final bool enabled;
  final ValueChanged<ActionType> onActionSelected;
  final VoidCallback onEraserSelected;
  final ValueChanged<TileColor> onConditionSelected;

  const InstructionPalette({
    super.key,
    required this.availableActions,
    required this.selectedAction,
    required this.eraserSelected,
    required this.selectedCondition,
    this.enabled = true,
    required this.onActionSelected,
    required this.onEraserSelected,
    required this.onConditionSelected,
  });

  static const Duration _dragHoldDelay = Duration(milliseconds: 200);

  // The feedback icon is lifted above the finger so it isn't hidden by it.
  // dragStartPoint anchors the *rendered* feedback that far above/centered
  // on the touch point; feedbackOffset shifts the *drop hit-test* by the
  // same amount, so whichever slot the icon visually sits over is the one
  // that actually receives it (Draggable hit-tests the raw pointer unless
  // feedbackOffset compensates for a transformed/anchored feedback).
  static const double _actionSize = 46;
  static const double _dotSize = 32;
  static const double _dragLift = 56;
  static const Offset _feedbackOffset = Offset(0, -_dragLift);

  static Offset _actionDragAnchor(Draggable<Object> draggable, BuildContext context, Offset position) {
    return const Offset(_actionSize / 2, _dragLift + _actionSize / 2);
  }

  static Offset _dotDragAnchor(Draggable<Object> draggable, BuildContext context, Offset position) {
    return const Offset(_dotSize / 2, _dragLift + _dotSize / 2);
  }

  @override
  Widget build(BuildContext context) {
    // forward, turnLeft, turnRight always come first (see _baseActions in
    // game_screen.dart) — the condition dots slot in right after those.
    final movementActions = availableActions.take(3);
    final remainingActions = availableActions.skip(3);

    return IgnorePointer(
      ignoring: !enabled,
      child: AnimatedOpacity(
        opacity: enabled ? 1 : 0.4,
        duration: const Duration(milliseconds: 180),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          decoration: BoxDecoration(
            color: AppColors.panel,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.panelBorder),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final action in movementActions) _buildActionButton(action),
                for (final color in TileColor.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: LongPressDraggable<TileColor>(
                      data: color,
                      delay: _dragHoldDelay,
                      dragAnchorStrategy: _dotDragAnchor,
                      feedbackOffset: _feedbackOffset,
                      feedback: Material(
                        type: MaterialType.transparency,
                        child: _ColorDot(color: color, selected: true, onTap: () {}),
                      ),
                      childWhenDragging: Opacity(
                        opacity: 0.3,
                        child: _ColorDot(color: color, selected: false, onTap: () {}),
                      ),
                      child: _ColorDot(
                        color: color,
                        selected: selectedCondition == color,
                        onTap: () => onConditionSelected(color),
                      ),
                    ),
                  ),
                const SizedBox(width: 2),
                Container(width: 1, height: 30, color: AppColors.panelBorder),
                const SizedBox(width: 10),
                for (final action in remainingActions) _buildActionButton(action),
                _ActionButton(
                  selected: eraserSelected,
                  onTap: onEraserSelected,
                  child: const Icon(Icons.backspace_outlined, size: 19, color: Colors.white),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton(ActionType action) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: LongPressDraggable<ProgramInstruction>(
        data: ProgramInstruction(action, condition: selectedCondition),
        delay: _dragHoldDelay,
        dragAnchorStrategy: _actionDragAnchor,
        feedbackOffset: _feedbackOffset,
        feedback: Material(
          type: MaterialType.transparency,
          child: _ActionButton(
            selected: true,
            onTap: () {},
            child: actionGlyph(action, size: 22, color: Colors.white),
          ),
        ),
        childWhenDragging: Opacity(
          opacity: 0.3,
          child: _ActionButton(
            selected: false,
            onTap: () {},
            child: actionGlyph(action, size: 22, color: Colors.white),
          ),
        ),
        child: _ActionButton(
          selected: !eraserSelected && selectedAction == action,
          onTap: () => onActionSelected(action),
          child: actionGlyph(action, size: 22, color: Colors.white),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  const _ActionButton({required this.selected, required this.onTap, required this.child});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 46,
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.selectionFill : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppColors.selectionBorder : Colors.white.withValues(alpha: 0.15),
            width: selected ? 2 : 1,
          ),
        ),
        child: child,
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  final TileColor color;
  final bool selected;
  final VoidCallback onTap;

  const _ColorDot({required this.color, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isAny = color == TileColor.any;
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isAny ? Colors.white.withValues(alpha: 0.08) : color.uiColor,
          border: Border.all(
            color: selected ? Colors.white : Colors.white.withValues(alpha: 0.25),
            width: selected ? 2.5 : 1.5,
          ),
        ),
        child: isAny
            ? Icon(Icons.clear_rounded, size: 16, color: Colors.white.withValues(alpha: 0.6))
            : null,
      ),
    );
  }
}
