import 'dart:async';
import 'dart:math' as math;

import 'package:sensors_plus/sensors_plus.dart';

/// Detects a device shake via the accelerometer (gravity already excluded,
/// since this reads [userAccelerometerEventStream] rather than the raw
/// sensor) and calls [onShake]. Requires a handful of high-acceleration
/// samples within a short rolling window — not just one spike — so an
/// incidental bump or a phone jostling in a pocket doesn't trigger it, and
/// enforces a cooldown between triggers so one shake doesn't fire twice.
class ShakeDetector {
  ShakeDetector({required this.onShake, Stream<UserAccelerometerEvent>? events})
      : _events = events ?? userAccelerometerEventStream();

  final void Function() onShake;
  final Stream<UserAccelerometerEvent> _events;

  static const double _threshold = 18.0; // m/s^2 (gravity excluded)
  static const int _requiredSamples = 3;
  static const Duration _sampleWindow = Duration(milliseconds: 500);
  static const Duration _cooldown = Duration(seconds: 1);

  StreamSubscription<UserAccelerometerEvent>? _subscription;
  final List<DateTime> _recentSpikes = [];
  DateTime? _lastTriggered;

  void start() {
    _subscription ??= _events.listen(_onEvent);
  }

  void stop() {
    _subscription?.cancel();
    _subscription = null;
  }

  void _onEvent(UserAccelerometerEvent event) {
    final magnitude =
        math.sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
    if (magnitude < _threshold) return;

    final now = DateTime.now();
    if (_lastTriggered != null && now.difference(_lastTriggered!) < _cooldown) {
      return;
    }

    _recentSpikes.add(now);
    _recentSpikes.removeWhere((t) => now.difference(t) > _sampleWindow);
    if (_recentSpikes.length >= _requiredSamples) {
      _recentSpikes.clear();
      _lastTriggered = now;
      onShake();
    }
  }
}
