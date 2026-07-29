import 'package:flutter/material.dart';

import '../engine/interpreter.dart';
import '../models/instruction.dart';
import '../theme/app_colors.dart';
import 'action_glyph.dart';

class ControlBar extends StatelessWidget {
  final RunStatus status;
  final int? runSpeed; // null = paused, otherwise 1, 2, or 8
  final bool canStepBack;
  final int starsRemaining;
  final int totalStars;
  final List<List<ProgramInstruction>> pendingByFrame;
  final VoidCallback onStep;
  final VoidCallback onStepBack;
  final ValueChanged<int> onSetSpeed;
  final VoidCallback onReset;

  const ControlBar({
    super.key,
    required this.status,
    required this.runSpeed,
    required this.canStepBack,
    required this.starsRemaining,
    required this.totalStars,
    required this.pendingByFrame,
    required this.onStep,
    required this.onStepBack,
    required this.onSetSpeed,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final collected = totalStars - starsRemaining;
    final isAutoRunning = runSpeed != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.panel,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.panelBorder),
          ),
          child: Row(
            children: [
              const Icon(Icons.star_rounded, color: AppColors.star, size: 18),
              const SizedBox(width: 4),
              Text(
                '$collected/$totalStars',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  // reverse: true means a fresh scroll position (there's no
                  // controller to preserve one) starts at the *end* of the
                  // content instead of the start, so a long call stack keeps
                  // its most recent (currently executing) frame in view
                  // instead of being cut off, without needing to manage a
                  // ScrollController just to jump to it on every rebuild.
                  reverse: true,
                  child: KeyedSubtree(
                    key: const ValueKey('controlBarStatusText'),
                    child: status == RunStatus.running
                        // Icons, not text abbreviations, for the same
                        // actions the palette and function slots already
                        // draw as icons (forward/turn/paint) — a
                        // different glyph for the same instruction here
                        // would just be one more thing to learn.
                        ? Semantics(
                            label: _pendingStackText(),
                            child: _PendingStackGlyphs(
                              groups: _pendingGroups(),
                              color: _statusColor(),
                            ),
                          )
                        : Text(
                            _statusText(),
                            style: TextStyle(
                              color: _statusColor(),
                              fontWeight: FontWeight.w600,
                              fontSize: 12.5,
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Wrap, not a horizontally-scrolling Row: these buttons should
        // always fit on one line, but a scrollable here would plant a
        // horizontal-drag recognizer flush against the left edge of the
        // screen, which iOS's edge-swipe-to-go-back gesture also wants —
        // the two would randomly compete for the same touch. Wrap only
        // grabs a gesture per-button (each is its own tap target), so
        // there's nothing to steal the swipe.
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _RoundIconButton(icon: Icons.refresh_rounded, onTap: onReset),
            _RoundIconButton(
              icon: Icons.skip_previous_rounded,
              onTap: (canStepBack && !isAutoRunning) ? onStepBack : null,
            ),
            _RoundIconButton(
              icon: Icons.skip_next_rounded,
              onTap: (!status.isTerminal && !isAutoRunning) ? onStep : null,
            ),
            Container(width: 1, height: 30, color: AppColors.panelBorder),
            for (final speed in [1, 2, 8])
              _SpeedButton(
                key: ValueKey('speed_${speed}x'),
                // >, >>, >>> for 1x/2x/8x instead of a numeric label.
                arrowCount: speed == 1
                    ? 1
                    : speed == 2
                        ? 2
                        : 3,
                active: runSpeed == speed,
                onTap: status.isTerminal ? null : () => onSetSpeed(speed),
              ),
          ],
        ),
      ],
    );
  }

  String _statusText() {
    switch (status) {
      case RunStatus.notStarted:
        return 'Ready';
      case RunStatus.running:
        return _pendingStackText();
      case RunStatus.success:
        return 'Solved!';
      case RunStatus.crashed:
        return 'Crashed — robot walked off a tile';
      case RunStatus.outOfInstructions:
        return 'Out of instructions — stars remain';
      case RunStatus.stuck:
        return 'Stuck — looks like an infinite loop';
    }
  }

  /// Each stack frame's remaining instructions, grouped outermost first —
  /// which function is active tells you nothing once several frames are
  /// the same function (recursion), but what's still queued in each does.
  /// Adjacent frames with identical remaining instructions (the common
  /// case for a straightforward recursive loop) collapse into one group
  /// with a repeat count instead of listing the same thing over and over.
  List<_PendingGroup> _pendingGroups() {
    final groups = <_PendingGroup>[];
    List<ProgramInstruction>? current;
    var repeat = 0;
    void flush() {
      if (current == null) return;
      groups.add(_PendingGroup(current, repeat));
    }

    bool sameInstructions(List<ProgramInstruction> a, List<ProgramInstruction> b) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (a[i].action != b[i].action || a[i].condition != b[i].condition) {
          return false;
        }
      }
      return true;
    }

    for (final pending in pendingByFrame) {
      if (current != null && sameInstructions(current, pending)) {
        repeat++;
      } else {
        flush();
        current = pending;
        repeat = 1;
      }
    }
    flush();
    return groups;
  }

  /// A screen-reader/accessibility-testing-friendly text rendition of
  /// [_pendingGroups] — the visible display uses real instruction glyphs.
  String _pendingStackText() => _pendingGroups()
      .map((g) {
        final label = g.instructions.map((i) => i.action.shortLabel).join(' ');
        final wrapped = g.instructions.length > 1 ? '($label)' : label;
        return g.repeat > 1 ? '$wrapped ×${g.repeat}' : wrapped;
      })
      .join('  →  ');

  Color _statusColor() {
    switch (status) {
      case RunStatus.success:
        return Colors.greenAccent.shade400;
      case RunStatus.crashed:
      case RunStatus.stuck:
      case RunStatus.outOfInstructions:
        return Colors.redAccent.shade100;
      default:
        return Colors.white70;
    }
  }
}

/// One collapsed run of stack frames sharing identical pending instructions.
class _PendingGroup {
  final List<ProgramInstruction> instructions;
  final int repeat;
  const _PendingGroup(this.instructions, this.repeat);
}

/// Renders [_PendingGroup]s as a single line of instruction glyphs — the
/// same [actionGlyph] the palette and function slots use — with light
/// punctuation ("(", ")", "×N", "→") to mark grouping and repetition.
class _PendingStackGlyphs extends StatelessWidget {
  final List<_PendingGroup> groups;
  final Color color;

  const _PendingStackGlyphs({required this.groups, required this.color});

  @override
  Widget build(BuildContext context) {
    final punctuationStyle = TextStyle(
      color: color,
      fontWeight: FontWeight.w600,
      fontSize: 12.5,
    );
    final children = <Widget>[];
    for (var g = 0; g < groups.length; g++) {
      if (g > 0) {
        children.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text('→', style: punctuationStyle),
        ));
      }
      final group = groups[g];
      final grouped = group.instructions.length > 1;
      if (grouped) children.add(Text('(', style: punctuationStyle));
      for (var i = 0; i < group.instructions.length; i++) {
        if (i > 0) children.add(const SizedBox(width: 3));
        children.add(actionGlyph(group.instructions[i].action, size: 15, color: color));
      }
      if (grouped) children.add(Text(')', style: punctuationStyle));
      if (group.repeat > 1) {
        children.add(Text(' ×${group.repeat}', style: punctuationStyle));
      }
    }
    return Row(mainAxisSize: MainAxisSize.min, children: children);
  }
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _RoundIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color:
              disabled ? Colors.white.withValues(alpha: 0.06) : AppColors.panel,
          border: Border.all(color: AppColors.panelBorder),
        ),
        child: Icon(icon,
            color: disabled ? Colors.white24 : Colors.white, size: 21),
      ),
    );
  }
}

class _SpeedButton extends StatelessWidget {
  // Overlapping ">" glyphs (step < size) read as a single ">>"/">>>" glyph
  // train rather than separate, evenly-spaced arrows.
  static const double _arrowSize = 20;
  static const double _arrowStep = 10;

  final int arrowCount;
  final bool active;
  final VoidCallback? onTap;

  const _SpeedButton(
      {super.key,
      required this.arrowCount,
      required this.active,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    // An explicit width, not just a minWidth + Alignment.center to shrink-
    // wrap the content: that shrink-wrap only happens to work under a Row,
    // which hands non-flex children an unbounded max width; under a Wrap
    // (bounded-but-generous max width per child) Alignment.center's
    // "expand to fill" default would stretch this to the *entire* Wrap
    // width instead of hugging its content.
    final contentWidth = active ? _arrowSize : _arrowSize + (arrowCount - 1) * _arrowStep;
    final width = contentWidth + 20 > 44 ? contentWidth + 20 : 44.0;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: width,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: disabled
              ? Colors.white.withValues(alpha: 0.06)
              : (active ? AppColors.accent : AppColors.panel),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: active ? AppColors.accent : AppColors.panelBorder),
        ),
        child: active
            ? Icon(Icons.pause_rounded,
                size: 20, color: disabled ? Colors.white24 : Colors.white)
            : SizedBox(
                width: _arrowSize + (arrowCount - 1) * _arrowStep,
                height: _arrowSize,
                child: Stack(
                  children: [
                    for (var i = 0; i < arrowCount; i++)
                      Positioned(
                        left: i * _arrowStep,
                        child: Icon(
                          Icons.play_arrow_rounded,
                          size: _arrowSize,
                          color: disabled ? Colors.white24 : Colors.white,
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}
