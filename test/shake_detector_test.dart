import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sensors_plus/sensors_plus.dart';

import 'package:robozzle_reboot/utils/shake_detector.dart';

UserAccelerometerEvent _event(double magnitude) =>
    UserAccelerometerEvent(magnitude, 0, 0, DateTime.now());

void main() {
  test('fires onShake after enough high-acceleration samples land close together', () async {
    final controller = StreamController<UserAccelerometerEvent>();
    var shakeCount = 0;
    final detector =
        ShakeDetector(onShake: () => shakeCount++, events: controller.stream);
    detector.start();
    addTearDown(() {
      detector.stop();
      controller.close();
    });

    controller.add(_event(20));
    controller.add(_event(20));
    controller.add(_event(20));
    await Future.delayed(Duration.zero);

    expect(shakeCount, 1);
  });

  test('ignores samples below the shake threshold', () async {
    final controller = StreamController<UserAccelerometerEvent>();
    var shakeCount = 0;
    final detector =
        ShakeDetector(onShake: () => shakeCount++, events: controller.stream);
    detector.start();
    addTearDown(() {
      detector.stop();
      controller.close();
    });

    for (var i = 0; i < 5; i++) {
      controller.add(_event(5));
    }
    await Future.delayed(Duration.zero);

    expect(shakeCount, 0);
  });

  test('does not fire again immediately after triggering (cooldown)', () async {
    final controller = StreamController<UserAccelerometerEvent>();
    var shakeCount = 0;
    final detector =
        ShakeDetector(onShake: () => shakeCount++, events: controller.stream);
    detector.start();
    addTearDown(() {
      detector.stop();
      controller.close();
    });

    for (var i = 0; i < 6; i++) {
      controller.add(_event(20));
    }
    await Future.delayed(Duration.zero);

    expect(shakeCount, 1);
  });

  test('stop() prevents further events from triggering onShake', () async {
    final controller = StreamController<UserAccelerometerEvent>();
    var shakeCount = 0;
    final detector =
        ShakeDetector(onShake: () => shakeCount++, events: controller.stream);
    detector.start();
    detector.stop();
    addTearDown(() => controller.close());

    controller.add(_event(20));
    controller.add(_event(20));
    controller.add(_event(20));
    await Future.delayed(Duration.zero);

    expect(shakeCount, 0);
  });
}
