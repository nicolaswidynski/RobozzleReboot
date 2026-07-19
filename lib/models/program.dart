import 'instruction.dart';
import 'level.dart';

/// One of the 5 functions (F1..F5) the player builds. Each slot is either
/// empty (null) or holds a [ProgramInstruction].
class ProgramFunction {
  final List<ProgramInstruction?> slots;

  ProgramFunction(int slotCount)
      : slots = List<ProgramInstruction?>.filled(slotCount, null);

  ProgramFunction.from(List<ProgramInstruction?> slots)
      : slots = List<ProgramInstruction?>.from(slots);

  ProgramFunction clone() => ProgramFunction.from(slots);
}

/// The player's full program: up to 5 functions, sized to match the level.
class RobotProgram {
  final List<ProgramFunction> functions;

  RobotProgram.empty(Level level)
      : functions = level.slotsPerFunction
            .map((count) => ProgramFunction(count))
            .toList(growable: false);

  RobotProgram clone() {
    final copy = RobotProgram._(
      functions.map((f) => f.clone()).toList(growable: false),
    );
    return copy;
  }

  RobotProgram._(this.functions);

  void setSlot(int functionIndex, int slotIndex, ProgramInstruction? value) {
    functions[functionIndex].slots[slotIndex] = value;
  }

  void clearAll() {
    for (final fn in functions) {
      for (var i = 0; i < fn.slots.length; i++) {
        fn.slots[i] = null;
      }
    }
  }
}
