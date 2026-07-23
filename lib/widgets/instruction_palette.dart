import 'package:flutter/material.dart';

import '../models/instruction.dart';
import '../models/tile_color.dart';
import '../theme/app_colors.dart';
import 'action_glyph.dart';
import 'tile_color_ui.dart';

/// The bottom toolbox: movement, condition colors, paint colors, and
/// F1..F5 subroutine calls, all on one line. Every action and color is a
/// drag source — long-press one and drag it onto a slot in a
/// [FunctionPanel] to place it (a color dot only accepts onto an
/// already-filled slot, to set its condition). There's no tap-to-select
/// step; dragging a placed instruction out to empty space removes it, so
/// there's no separate eraser either.
///
/// The line paginates with `<`/`>` buttons ([_PaginatedRow]) rather than
/// scrolling — with the drag hold delay at 0ms, any sideways swipe to
/// scroll the line is immediately read as the start of a drag instead, so
/// free-scrolling doesn't work here.
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

  static Offset _dotDragAnchor(
      Draggable<Object> draggable, BuildContext context, Offset position) {
    return const Offset(_dotSize / 2, _dragLift + _dotSize / 2);
  }

  @override
  Widget build(BuildContext context) {
    // forward, turnLeft, turnRight always come first (see _baseActions in
    // game_screen.dart) — the paint colors, when allowed, and F1..F5 calls
    // follow, in that order.
    final movementActions = availableActions.take(3);
    final paintActions =
        availableActions.where((a) => _paintActions.contains(a));
    final callActions = availableActions.where((a) => a.isCall);

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
          child: _PaginatedRow(
            children: [
              for (final action in movementActions) _buildActionButton(action),
              for (final color in _conditionColors) _buildColorDot(color),
              if (paintActions.isNotEmpty) ...[
                const SizedBox(width: 2),
                Container(width: 1, height: 24, color: AppColors.panelBorder),
                const SizedBox(width: 10),
                for (final action in paintActions) _buildActionButton(action),
              ],
              if (callActions.isNotEmpty) ...[
                const SizedBox(width: 2),
                Container(width: 1, height: 24, color: AppColors.panelBorder),
                const SizedBox(width: 10),
                for (final action in callActions) _buildActionButton(action),
              ],
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

  Widget _buildColorDot(TileColor color) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: LongPressDraggable<TileColor>(
        data: color,
        delay: _dragHoldDelay,
        dragAnchorStrategy: _dotDragAnchor,
        feedbackOffset: _feedbackOffset,
        feedback: Material(
          type: MaterialType.transparency,
          child: _ColorDot(color: color),
        ),
        childWhenDragging:
            Opacity(opacity: 0.3, child: _ColorDot(color: color)),
        child: _ColorDot(color: color),
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

/// One line of the palette: [children] laid out in a row that never
/// responds to a drag/swipe itself (`NeverScrollableScrollPhysics` — a
/// sideways swipe here would otherwise be indistinguishable from starting
/// to drag one of the 0ms-delay draggables inside it), paginated instead by
/// the `<`/`>` buttons, which animate exactly one viewport's worth at a
/// time. Both buttons stay visible but go inert (and dim) at either end,
/// same as ControlBar's step-back button.
class _PaginatedRow extends StatefulWidget {
  final List<Widget> children;

  const _PaginatedRow({required this.children});

  @override
  State<_PaginatedRow> createState() => _PaginatedRowState();
}

class _PaginatedRowState extends State<_PaginatedRow> {
  static const Duration _pageDuration = Duration(milliseconds: 220);

  final ScrollController _controller = ScrollController();
  bool _canPageBack = false;
  bool _canPageForward = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_updateArrows);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateArrows());
  }

  @override
  void dispose() {
    _controller.removeListener(_updateArrows);
    _controller.dispose();
    super.dispose();
  }

  void _updateArrows() {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    final canBack = position.pixels > position.minScrollExtent + 0.5;
    final canForward = position.pixels < position.maxScrollExtent - 0.5;
    if (canBack != _canPageBack || canForward != _canPageForward) {
      setState(() {
        _canPageBack = canBack;
        _canPageForward = canForward;
      });
    }
  }

  void _page(double direction) {
    final position = _controller.position;
    final target = (_controller.offset + direction * position.viewportDimension)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    _controller.animateTo(target, duration: _pageDuration, curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PageButton(
          icon: Icons.keyboard_arrow_left_rounded,
          onTap: _canPageBack ? () => _page(-1) : null,
        ),
        Flexible(
          child: SingleChildScrollView(
            controller: _controller,
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            child: Row(children: widget.children),
          ),
        ),
        _PageButton(
          icon: Icons.keyboard_arrow_right_rounded,
          onTap: _canPageForward ? () => _page(1) : null,
        ),
      ],
    );
  }
}

class _PageButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _PageButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 14),
        child: Icon(
          icon,
          size: 22,
          color: onTap == null
              ? Colors.white.withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.7),
        ),
      ),
    );
  }
}
