import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:robozzle_reboot/data/program_store.dart';
import 'package:robozzle_reboot/models/instruction.dart';
import 'package:robozzle_reboot/models/program.dart';
import 'package:robozzle_reboot/models/tile_color.dart';

import 'test_level.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('loadSolved returns null when nothing was ever saved', () async {
    final level = testLevel();
    expect(await ProgramStore().loadSolved(level), isNull);
  });

  test('saveSolved then loadSolved round-trips instructions, conditions, '
      'and empty slots exactly', () async {
    final level = testLevel();
    final program = RobotProgram.empty(level);
    program.setSlot(0, 0, const ProgramInstruction(ActionType.forward));
    program.setSlot(
      0,
      1,
      const ProgramInstruction(ActionType.turnRight, condition: TileColor.red),
    );
    // slot 2 left empty (null) deliberately.
    program.setSlot(0, 3, const ProgramInstruction(ActionType.callF2));

    final store = ProgramStore();
    await store.saveSolved(level, program);
    final loaded = await store.loadSolved(level);

    expect(loaded, isNotNull);
    expect(loaded!.functions[0].slots[0]?.action, ActionType.forward);
    expect(loaded.functions[0].slots[0]?.condition, TileColor.any);
    expect(loaded.functions[0].slots[1]?.action, ActionType.turnRight);
    expect(loaded.functions[0].slots[1]?.condition, TileColor.red);
    expect(loaded.functions[0].slots[2], isNull);
    expect(loaded.functions[0].slots[3]?.action, ActionType.callF2);
  });

  test('is scoped per level id — saving one level does not affect another',
      () async {
    final level = testLevel();
    final level2 = testLevel2();
    final program = RobotProgram.empty(level);
    program.setSlot(0, 0, const ProgramInstruction(ActionType.forward));

    final store = ProgramStore();
    await store.saveSolved(level, program);

    expect(await store.loadSolved(level2), isNull);
    expect(await store.loadSolved(level), isNotNull);
  });
}
