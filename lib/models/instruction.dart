import 'tile_color.dart';

/// The action an instruction performs. [callF1]..[callF5] invoke another
/// function (subroutine), enabling loops and recursion.
enum ActionType {
  forward,
  turnLeft,
  turnRight,
  paintRed,
  paintGreen,
  paintBlue,
  callF1,
  callF2,
  callF3,
  callF4,
  callF5,
}

extension ActionTypeData on ActionType {
  bool get isCall => index >= ActionType.callF1.index;

  /// Which function index (0-based) this call jumps to.
  int get callTarget => index - ActionType.callF1.index;

  String get shortLabel {
    switch (this) {
      case ActionType.forward:
        return '↑';
      case ActionType.turnLeft:
        return '↺';
      case ActionType.turnRight:
        return '↻';
      case ActionType.paintRed:
        return 'Paint R';
      case ActionType.paintGreen:
        return 'Paint G';
      case ActionType.paintBlue:
        return 'Paint B';
      case ActionType.callF1:
        return 'F1';
      case ActionType.callF2:
        return 'F2';
      case ActionType.callF3:
        return 'F3';
      case ActionType.callF4:
        return 'F4';
      case ActionType.callF5:
        return 'F5';
    }
  }
}

/// One instruction placed in a function slot: an action plus an optional
/// color condition. If [condition] is not [TileColor.any], the instruction
/// only executes when the robot is standing on a tile of that color.
class ProgramInstruction {
  final ActionType action;
  final TileColor condition;

  const ProgramInstruction(this.action, {this.condition = TileColor.any});

  ProgramInstruction copyWith({ActionType? action, TileColor? condition}) {
    return ProgramInstruction(
      action ?? this.action,
      condition: condition ?? this.condition,
    );
  }
}
