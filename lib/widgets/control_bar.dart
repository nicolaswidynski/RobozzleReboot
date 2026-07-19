import 'package:flutter/material.dart';

import '../engine/interpreter.dart';
import '../theme/app_colors.dart';

class ControlBar extends StatelessWidget {
  final RunStatus status;
  final int? runSpeed; // null = paused, otherwise 1, 2, or 8
  final bool canStepBack;
  final int starsRemaining;
  final int totalStars;
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
                child: Text(
                  _statusText(),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _statusColor(),
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _RoundIconButton(icon: Icons.refresh_rounded, onTap: onReset),
              const SizedBox(width: 8),
              _RoundIconButton(
                icon: Icons.skip_previous_rounded,
                onTap: (canStepBack && !isAutoRunning) ? onStepBack : null,
              ),
              const SizedBox(width: 8),
              _RoundIconButton(
                icon: Icons.skip_next_rounded,
                onTap: (!status.isTerminal && !isAutoRunning) ? onStep : null,
              ),
              const SizedBox(width: 10),
              Container(width: 1, height: 30, color: AppColors.panelBorder),
              const SizedBox(width: 10),
              for (final speed in [1, 2, 8]) ...[
                _SpeedButton(
                  // Plain play button for normal speed — "1x" is redundant.
                  label: speed == 1 ? null : '${speed}x',
                  active: runSpeed == speed,
                  onTap: status.isTerminal ? null : () => onSetSpeed(speed),
                ),
                if (speed != 8) const SizedBox(width: 8),
              ],
            ],
          ),
        ),
      ],
    );
  }

  String _statusText() {
    switch (status) {
      case RunStatus.notStarted:
        return 'Ready';
      case RunStatus.running:
        return 'Running…';
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
  final String? label;
  final bool active;
  final VoidCallback? onTap;

  const _SpeedButton(
      {required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        constraints: const BoxConstraints(minWidth: 44),
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: disabled
              ? Colors.white.withValues(alpha: 0.06)
              : (active ? AppColors.accent : AppColors.panel),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: active ? AppColors.accent : AppColors.panelBorder),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              active ? Icons.pause_rounded : Icons.play_arrow_rounded,
              size: 20,
              color: disabled ? Colors.white24 : Colors.white,
            ),
            if (label != null) ...[
              const SizedBox(width: 3),
              Text(
                label!,
                style: TextStyle(
                  color: disabled ? Colors.white24 : Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
