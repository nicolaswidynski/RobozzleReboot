import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/instruction.dart';
import '../models/level.dart';
import '../models/program.dart';
import '../models/tile_color.dart';

/// Persists whatever program the player has built for a level, keyed by
/// [Level.id] — saved on every edit, not just once solved — so reopening a
/// level restores whatever was last there instead of starting blank.
class ProgramStore {
  static const _keyPrefix = 'program_';

  Future<void> save(Level level, RobotProgram program) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = program.functions
        .map((fn) => fn.slots.map(_encodeSlot).toList())
        .toList();
    await prefs.setString('$_keyPrefix${level.id}', jsonEncode(encoded));
  }

  /// Returns `null` if nothing was ever saved for this level, or if the
  /// saved data doesn't parse (e.g. it was written by an older/incompatible
  /// version) — the caller should just fall back to a blank program.
  Future<RobotProgram?> load(Level level) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_keyPrefix${level.id}');
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw) as List;
      final program = RobotProgram.empty(level);
      for (var fi = 0;
          fi < decoded.length && fi < program.functions.length;
          fi++) {
        final slots = decoded[fi] as List;
        final target = program.functions[fi].slots;
        for (var si = 0; si < slots.length && si < target.length; si++) {
          target[si] = _decodeSlot(slots[si] as String?);
        }
      }
      return program;
    } catch (_) {
      return null;
    }
  }

  String? _encodeSlot(ProgramInstruction? instruction) {
    if (instruction == null) return null;
    return '${instruction.action.name}:${instruction.condition.name}';
  }

  ProgramInstruction? _decodeSlot(String? raw) {
    if (raw == null) return null;
    final parts = raw.split(':');
    return ProgramInstruction(
      ActionType.values.byName(parts[0]),
      condition: TileColor.values.byName(parts[1]),
    );
  }
}
