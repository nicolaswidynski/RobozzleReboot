import 'package:flutter/material.dart';

import '../models/instruction.dart';
import '../models/program.dart';
import '../models/tile_color.dart';
import '../theme/app_colors.dart';
import 'action_glyph.dart';
import 'dashed_border.dart';
import 'group_selection.dart';
import 'tile_color_ui.dart';

/// Carries a filled slot's instruction plus its origin (function + slot
/// index) while it's being long-press-dragged to another slot, so the
/// destination can move it — the source is only cleared once a target
/// actually accepts the drop, not just because a drag started.
class SlotInstructionMove {
  final int functionIndex;
  final int slotIndex;
  final ProgramInstruction instruction;

  const SlotInstructionMove({
    required this.functionIndex,
    required this.slotIndex,
    required this.instruction,
  });
}

/// One function's (F1..F5) instruction slots: an "F1"-style label to the
/// left, and its slots laid out in fixed rows of [_slotsPerRow] — all slots
/// always visible at once, no horizontal scrolling. Every slot is a drop
/// target only — an instruction long-press-dragged in from the palette
/// ([onSlotDrop]), a color dragged in to set just its condition
/// ([onConditionDrop]), or an instruction dragged in from another slot to
/// move it there ([onSlotMove]). There's no tap-to-place.
///
/// Whether this panel is visible at all is controlled by the parent (all
/// functions show/hide together via a single swipe gesture, not per-panel).
class FunctionPanel extends StatelessWidget {
  static const int _slotsPerRow = 6;

  final String label;
  final int functionIndex;
  final ProgramFunction function;
  final int? highlightSlot;
  final void Function(int slotIndex, ProgramInstruction instruction) onSlotDrop;
  final void Function(int slotIndex, TileColor color) onConditionDrop;
  final void Function(int slotIndex, SlotInstructionMove move) onSlotMove;
  final void Function(int slotIndex) onSlotRemove;

  const FunctionPanel({
    super.key,
    required this.label,
    required this.functionIndex,
    required this.function,
    required this.highlightSlot,
    required this.onSlotDrop,
    required this.onConditionDrop,
    required this.onSlotMove,
    required this.onSlotRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.panelBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.accent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              children: [
                for (var start = 0;
                    start < function.slots.length;
                    start += _slotsPerRow) ...[
                  if (start > 0) const SizedBox(height: 6),
                  Row(
                    children: [
                      for (var i = start;
                          i <
                              (start + _slotsPerRow)
                                  .clamp(0, function.slots.length);
                          i++)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: _SlotBox(
                            functionIndex: functionIndex,
                            slotIndex: i,
                            instruction: function.slots[i],
                            highlighted: highlightSlot == i,
                            onDrop: (instr) => onSlotDrop(i, instr),
                            onConditionDrop: (color) =>
                                onConditionDrop(i, color),
                            onMove: (move) => onSlotMove(i, move),
                            onRemove: () => onSlotRemove(i),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SlotBox extends StatelessWidget {
  static const Duration _dragHoldDelay = Duration.zero;
  static const double _slotSize = 42;
  static const double _dragLift = 56;
  static const Offset _feedbackOffset = Offset(0, -_dragLift);

  static Offset _dragAnchor(
      Draggable<Object> draggable, BuildContext context, Offset position) {
    return const Offset(_slotSize / 2, _dragLift + _slotSize / 2);
  }

  final int functionIndex;
  final int slotIndex;
  final ProgramInstruction? instruction;
  final bool highlighted;
  final ValueChanged<ProgramInstruction> onDrop;
  final ValueChanged<TileColor> onConditionDrop;
  final ValueChanged<SlotInstructionMove> onMove;
  final VoidCallback onRemove;

  const _SlotBox({
    required this.functionIndex,
    required this.slotIndex,
    required this.instruction,
    required this.highlighted,
    required this.onDrop,
    required this.onConditionDrop,
    required this.onMove,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final hasCondition =
        instruction != null && instruction!.condition != TileColor.any;
    final fillColor = instruction == null
        ? Colors.transparent
        : (hasCondition
            ? instruction!.condition.uiColor.withValues(alpha: 0.28)
            : Colors.white.withValues(alpha: 0.08));

    // Dropping a color dot (from the palette) onto a slot that already holds
    // an instruction sets/replaces just its condition, leaving the action
    // alone; an empty slot rejects it since there's nothing to attach to.
    // The GroupSelection<ProgramInstruction> layer mirrors the plain
    // ProgramInstruction one below, for a grouped palette button's drag
    // (paint/F-calls) — its data isn't known until the drop, once the
    // player's finger has swept past the button's fan-out menu and settled
    // on one option. Condition colors are never grouped, so there's no
    // GroupSelection<TileColor> layer — the plain TileColor one below is
    // all they ever need.
    return DragTarget<GroupSelection<ProgramInstruction>>(
      onWillAcceptWithDetails: (details) => details.data.value != null,
      onAcceptWithDetails: (details) {
        final instr = details.data.value;
        if (instr != null) onDrop(instr);
      },
      builder: (context, groupInstrCandidates, _) {
        final isGroupInstrHovering = groupInstrCandidates.isNotEmpty;
        return DragTarget<TileColor>(
          onWillAcceptWithDetails: (details) => instruction != null,
          onAcceptWithDetails: (details) => onConditionDrop(details.data),
          builder: (context, colorCandidates, colorRejected) {
            final isColorHovering = colorCandidates.isNotEmpty;
            // An instruction dragged in from another slot moves it
            // here. Dropping on itself is accepted too — it's a
            // same-slot move (source cleared, then immediately
            // re-set), a harmless no-op — rather than rejected, so
            // that only a *true* drop outside any slot (nothing
            // accepts it) reads as "cancelled" and removes it.
            return DragTarget<SlotInstructionMove>(
              onAcceptWithDetails: (details) => onMove(details.data),
              builder: (context, moveCandidates, moveRejected) {
                final isMoveHovering = moveCandidates.isNotEmpty;
                return DragTarget<ProgramInstruction>(
                  onAcceptWithDetails: (details) => onDrop(details.data),
                  builder: (context, candidateData, rejectedData) {
                    final isHovering = candidateData.isNotEmpty ||
                        isColorHovering ||
                        isMoveHovering ||
                        isGroupInstrHovering;
                    final box = Container(
                      width: _slotSize,
                      height: _slotSize,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isHovering ? AppColors.selectionFill : fillColor,
                        borderRadius: BorderRadius.circular(8),
                        border: isHovering
                            ? Border.all(
                                color: AppColors.selectionBorder, width: 2.5)
                            : (highlighted
                                ? Border.all(
                                    color: AppColors.runningHighlight, width: 2.5)
                                : (hasCondition
                                    ? Border.all(
                                        color: instruction!.condition.uiColor,
                                        width: 1.5)
                                    : null)),
                      ),
                      child: instruction == null
                          ? null
                          : actionGlyph(instruction!.action, size: 20),
                    );

                    final content = instruction == null
                        ? DashedRoundedBorder(
                            radius: 8,
                            color: isHovering
                                ? AppColors.selectionBorder
                                : AppColors.dashedSlot,
                            child: box,
                          )
                        : box;

                    if (instruction == null) {
                      return content;
                    }

                    return LongPressDraggable<SlotInstructionMove>(
                      data: SlotInstructionMove(
                        functionIndex: functionIndex,
                        slotIndex: slotIndex,
                        instruction: instruction!,
                      ),
                      delay: _dragHoldDelay,
                      dragAnchorStrategy: _dragAnchor,
                      feedbackOffset: _feedbackOffset,
                      // Dropped somewhere that didn't accept it
                      // (nothing but a slot does) — treat it as "drag
                      // it away to delete it".
                      onDraggableCanceled: (velocity, offset) => onRemove(),
                      feedback: Material(
                        type: MaterialType.transparency,
                        child: Container(
                          width: _slotSize,
                          height: _slotSize,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.selectionFill,
                            border: Border.all(
                                color: AppColors.selectionBorder, width: 2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: actionGlyph(instruction!.action, size: 20),
                        ),
                      ),
                      childWhenDragging:
                          Opacity(opacity: 0.3, child: content),
                      child: content,
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}
