import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/instruction.dart';
import '../models/tile_color.dart';
import '../theme/app_colors.dart';
import 'action_glyph.dart';
import 'group_selection.dart';
import 'tile_color_ui.dart';

/// The bottom toolbox: movement, condition colors, paint colors, and
/// F1..F5 subroutine calls, all on one line. Every action and color is a
/// drag source — long-press one and drag it onto a slot in a
/// [FunctionPanel] to place it (a color dot only accepts onto an
/// already-filled slot, to set its condition). There's no tap-to-select
/// step; dragging a placed instruction out to empty space removes it, so
/// there's no separate eraser either.
///
/// Condition colors, paint colors, and F-calls each collapse into a single
/// [_GroupButton] when the group has more than one option — press-and-hold
/// fans a vertical menu out above the button, and sliding up through it
/// (without lifting the finger) then continuing on to a slot commits
/// whichever option the drag was over when it left the menu. A group with
/// exactly one option skips the menu and is just that option's plain
/// button; a group with zero options isn't shown at all.
///
/// Frozen (dimmed and unresponsive) via [enabled] while the program is
/// auto-running, since edits mid-run don't apply until you stop anyway.
class InstructionPalette extends StatelessWidget {
  final List<ActionType> availableActions;
  final bool enabled;

  const InstructionPalette({
    super.key,
    required this.availableActions,
    this.enabled = true,
  });

  static const Duration _dragHoldDelay = Duration.zero;

  // [TileColor.any] is the "no condition" marker, not a real color to paint
  // a condition with — dragging an instruction out and a fresh one back in
  // is how a condition gets removed, so there's no "remove color" dot.
  static const List<TileColor> _conditionColors = [
    TileColor.red,
    TileColor.green,
    TileColor.blue,
  ];

  static const List<ActionType> _paintActions = [
    ActionType.paintRed,
    ActionType.paintGreen,
    ActionType.paintBlue,
  ];

  // The feedback icon is lifted above the finger so it isn't hidden by it.
  // dragStartPoint anchors the *rendered* feedback that far above/centered
  // on the touch point; feedbackOffset shifts the *drop hit-test* by the
  // same amount, so whichever slot the icon visually sits over is the one
  // that actually receives it (Draggable hit-tests the raw pointer unless
  // feedbackOffset compensates for a transformed/anchored feedback).
  static const double _actionSize = 48;
  static const double _dotSize = 30;
  static const double _dragLift = 56;
  static const Offset _feedbackOffset = Offset(0, -_dragLift);

  static Offset _actionDragAnchor(
      Draggable<Object> draggable, BuildContext context, Offset position) {
    return const Offset(_actionSize / 2, _dragLift + _actionSize / 2);
  }

  @override
  Widget build(BuildContext context) {
    // forward, turnLeft, turnRight always come first (see _baseActions in
    // game_screen.dart) — the paint colors, when allowed, and F1..F5 calls
    // follow, in that order.
    final movementActions = availableActions.take(3);
    final paintActions =
        availableActions.where((a) => _paintActions.contains(a)).toList();
    final callActions = availableActions.where((a) => a.isCall).toList();

    return IgnorePointer(
      ignoring: !enabled,
      child: AnimatedOpacity(
        opacity: enabled ? 1 : 0.4,
        duration: const Duration(milliseconds: 180),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
          decoration: BoxDecoration(
            color: AppColors.panel,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.panelBorder),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final action in movementActions) _buildActionButton(action),
              _buildColorGroup(),
              if (paintActions.isNotEmpty) _buildInstructionGroup(paintActions),
              if (callActions.isNotEmpty) _buildInstructionGroup(callActions),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton(ActionType action) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: LongPressDraggable<ProgramInstruction>(
        data: ProgramInstruction(action),
        delay: _dragHoldDelay,
        dragAnchorStrategy: _actionDragAnchor,
        feedbackOffset: _feedbackOffset,
        feedback: Material(
          type: MaterialType.transparency,
          child: _ActionButton(
            child: actionGlyph(action, size: 20, color: Colors.white),
          ),
        ),
        childWhenDragging: Opacity(
          opacity: 0.3,
          child: _ActionButton(
            child: actionGlyph(action, size: 20, color: Colors.white),
          ),
        ),
        child: _ActionButton(
          child: actionGlyph(action, size: 20, color: Colors.white),
        ),
      ),
    );
  }

  // Condition colors are always exactly 3 options, so this is always a
  // group button — no single-option fallback needed.
  Widget _buildColorGroup() {
    return _GroupButton<TileColor>(
      options: _conditionColors,
      itemSize: _dotSize,
      buttonBuilder: (color) => _ColorDot(color: color),
    );
  }

  Widget _buildInstructionGroup(List<ActionType> actions) {
    if (actions.length == 1) {
      return _buildActionButton(actions.first);
    }
    return _GroupButton<ProgramInstruction>(
      options: [for (final a in actions) ProgramInstruction(a)],
      itemSize: _actionSize,
      buttonBuilder: (instr) => _ActionButton(
        child: actionGlyph(instr.action, size: 20, color: Colors.white),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final Widget child;

  const _ActionButton({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: InstructionPalette._actionSize,
      height: InstructionPalette._actionSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
      ),
      child: child,
    );
  }
}

class _ColorDot extends StatelessWidget {
  final TileColor color;

  const _ColorDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: InstructionPalette._dotSize,
      height: InstructionPalette._dotSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.uiColor,
        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
      ),
    );
  }
}

/// A palette group (condition colors, paint colors, or F-calls) collapsed
/// into a single button. Long-pressing it starts a drag of a
/// [GroupSelection]<T> whose `value` starts out null and is filled in
/// mid-gesture: [_onDragStarted] fans a vertical menu of [options] out
/// above the button via an [OverlayEntry] (so it's pinned to a fixed
/// screen position rather than following the finger, unlike the drag
/// feedback); [_onDragUpdate] tracks how far up through the menu the
/// finger has travelled to highlight the hovered option, and once the
/// finger continues moving past the menu's far edge, that option is
/// written into the holder, the menu is torn down, and the feedback
/// switches from blank to that option's icon for the rest of the drag —
/// all as one continuous gesture, matching a normal placed drag from here
/// to a [FunctionPanel] slot.
class _GroupButton<T extends Object> extends StatefulWidget {
  final List<T> options;
  final double itemSize;
  final Widget Function(T option) buttonBuilder;

  const _GroupButton({
    required this.options,
    required this.itemSize,
    required this.buttonBuilder,
  });

  @override
  State<_GroupButton<T>> createState() => _GroupButtonState<T>();
}

class _GroupButtonState<T extends Object> extends State<_GroupButton<T>> {
  static const double _itemSpacing = 6;
  static const double _menuGap = 10;

  final GroupSelection<T> _holder = GroupSelection<T>();
  final GlobalKey _anchorKey = GlobalKey();
  final ValueNotifier<int> _hoveredIndex = ValueNotifier(0);
  final ValueNotifier<bool> _committed = ValueNotifier(false);
  OverlayEntry? _menuEntry;
  Offset _origin = Offset.zero;

  double get _itemStep => widget.itemSize + _itemSpacing;
  double get _menuHeight =>
      widget.options.length * widget.itemSize +
      (widget.options.length - 1) * _itemSpacing;
  // How far sideways off dead-center the finger can drift while still
  // "inside" the menu, browsing — a full item's width, so incidental
  // diagonal drift while sliding straight up doesn't count as leaving.
  double get _sidewaysSlop => widget.itemSize;

  Offset _dragAnchor(
      Draggable<Object> draggable, BuildContext context, Offset position) {
    return Offset(widget.itemSize / 2,
        InstructionPalette._dragLift + widget.itemSize / 2);
  }

  void _onDragStarted() {
    final box = _anchorKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null) {
      _origin = box.localToGlobal(box.size.center(Offset.zero));
    }
    _holder.value = null;
    _hoveredIndex.value = 0;
    _committed.value = false;
    _menuEntry?.remove();
    final entry = OverlayEntry(
      builder: (context) => _GroupMenu<T>(
        origin: _origin,
        options: widget.options,
        itemSize: widget.itemSize,
        itemSpacing: _itemSpacing,
        menuGap: _menuGap,
        buttonBuilder: widget.buttonBuilder,
        hoveredIndex: _hoveredIndex,
      ),
    );
    _menuEntry = entry;
    Overlay.of(context).insert(entry);
  }

  void _hideMenu() {
    _menuEntry?.remove();
    _menuEntry = null;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_committed.value) return;
    final delta = details.globalPosition - _origin;
    final upDistance = (-delta.dy).clamp(0.0, double.infinity);
    final index =
        (upDistance / _itemStep).floor().clamp(0, widget.options.length - 1);
    if (_hoveredIndex.value != index) _hoveredIndex.value = index;

    // While the finger stays roughly centered above the button, it's just
    // browsing the menu — vertical position alone picks the hovered item,
    // with no commit no matter how far up that goes. Committing instead
    // happens the moment the finger leaves that vertical lane (heading
    // sideways towards a slot) or overshoots past the top of the menu
    // entirely. This is what makes the *nearest* option always cheap to
    // reach regardless of how many options the group has — reaching a
    // farther option costs exactly the travel needed to get there, no
    // more — instead of every option costing however tall the whole menu
    // is.
    final exitedSideways = delta.dx.abs() > _sidewaysSlop;
    final exitedTop = upDistance > _menuHeight + _menuGap;
    if (exitedSideways || exitedTop) {
      _holder.value = widget.options[index];
      _committed.value = true;
      _hideMenu();
    }
  }

  void _onDragEnd(DraggableDetails details) {
    _hideMenu();
  }

  @override
  void dispose() {
    _hideMenu();
    _hoveredIndex.dispose();
    _committed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final resting = widget.buttonBuilder(widget.options.first);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: LongPressDraggable<GroupSelection<T>>(
        key: _anchorKey,
        data: _holder,
        delay: InstructionPalette._dragHoldDelay,
        dragAnchorStrategy: _dragAnchor,
        feedbackOffset: InstructionPalette._feedbackOffset,
        onDragStarted: _onDragStarted,
        onDragUpdate: _onDragUpdate,
        onDragEnd: _onDragEnd,
        feedback: ValueListenableBuilder<bool>(
          valueListenable: _committed,
          builder: (context, committed, _) {
            final value = _holder.value;
            if (!committed || value == null) {
              return const SizedBox.shrink();
            }
            return Material(
              type: MaterialType.transparency,
              child: widget.buttonBuilder(value),
            );
          },
        ),
        childWhenDragging: Opacity(opacity: 0.3, child: resting),
        child: _GroupBadge(child: resting),
      ),
    );
  }
}

/// A small dot in the corner of a group's resting button, hinting that
/// holding it opens more options instead of just placing the one shown.
class _GroupBadge extends StatelessWidget {
  final Widget child;

  const _GroupBadge({required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          right: -2,
          top: -2,
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.accent,
              border: Border.all(color: AppColors.panel, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}

/// The floating vertical fan-out menu for a [_GroupButton], hosted in an
/// [Overlay] so it's pinned to a fixed screen position (anchored to
/// [origin], the button's center at drag-start) rather than following the
/// finger. `IgnorePointer`-wrapped since it's purely a visual readout of
/// [hoveredIndex] — all touch handling stays on the original
/// `LongPressDraggable`, which keeps tracking the same pointer regardless
/// of what's drawn on top of it.
class _GroupMenu<T extends Object> extends StatelessWidget {
  final Offset origin;
  final List<T> options;
  final double itemSize;
  final double itemSpacing;
  final double menuGap;
  final Widget Function(T option) buttonBuilder;
  final ValueListenable<int> hoveredIndex;

  const _GroupMenu({
    required this.origin,
    required this.options,
    required this.itemSize,
    required this.itemSpacing,
    required this.menuGap,
    required this.buttonBuilder,
    required this.hoveredIndex,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: origin.dx,
      top: origin.dy - menuGap,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -1.0),
        child: IgnorePointer(
          child: ValueListenableBuilder<int>(
            valueListenable: hoveredIndex,
            builder: (context, hovered, _) {
              return Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.panel,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.panelBorder),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = options.length - 1; i >= 0; i--) ...[
                      if (i != options.length - 1) SizedBox(height: itemSpacing),
                      _MenuItem(
                        highlighted: hovered == i,
                        child: buttonBuilder(options[i]),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final bool highlighted;
  final Widget child;

  const _MenuItem({required this.highlighted, required this.child});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: highlighted ? AppColors.selectionFill : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: highlighted ? AppColors.selectionBorder : Colors.transparent,
          width: 2,
        ),
      ),
      child: child,
    );
  }
}

