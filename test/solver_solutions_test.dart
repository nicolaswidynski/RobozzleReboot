// Verifies the Rust solver's output (solver/solutions.json, see
// solver/SPEC.md §26) against the game's own interpreter: every solved
// program must succeed here, in exactly the number of steps the solver
// reported. Skipped when solutions.json has not been generated.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:robozzle_reboot/engine/interpreter.dart';
import 'package:robozzle_reboot/models/instruction.dart';
import 'package:robozzle_reboot/models/level.dart';
import 'package:robozzle_reboot/models/program.dart';
import 'package:robozzle_reboot/models/tile_color.dart';

/// Parses "<condition>:<action>" (condition omitted for Any).
ProgramInstruction _parseInstruction(String token) {
  final parts = token.split(':');
  final condition = parts.length == 2
      ? TileColor.values.byName(parts[0])
      : TileColor.any;
  return ProgramInstruction(
    ActionType.values.byName(parts.last),
    condition: condition,
  );
}

void main() {
  final solutionsFile = File('solver/solutions.json');
  if (!solutionsFile.existsSync()) {
    test('solver solutions', () {},
        skip: 'solver/solutions.json not found; run the solver first');
    return;
  }

  final catalog = {
    for (final entry
        in jsonDecode(File('assets/levels_catalog.json').readAsStringSync())
            as List)
      '${(entry as Map<String, dynamic>)['sourceId']}': entry,
  };
  final output =
      jsonDecode(solutionsFile.readAsStringSync()) as Map<String, dynamic>;
  final solved = (output['results'] as List)
      .cast<Map<String, dynamic>>()
      .where((r) => r['status'] == 'solved')
      .toList();

  test('solutions.json contains solved puzzles', () {
    expect(solved, isNotEmpty);
  });

  for (final result in solved) {
    final id = '${result['sourceId']}';
    test('puzzle $id: solver program succeeds in the game engine', () {
      final entry = catalog[id];
      expect(entry, isNotNull, reason: 'sourceId $id is not in the catalog');
      final level = Level.fromJson(entry!);
      final program = RobotProgram.empty(level);
      final functions = (result['program'] as List).cast<List>();
      for (var f = 0; f < functions.length; f++) {
        expect(functions[f].length, level.slotsPerFunction[f],
            reason: 'F${f + 1} must have exactly its capacity in slots');
        for (var i = 0; i < functions[f].length; i++) {
          final token = functions[f][i] as String?;
          if (token != null) program.setSlot(f, i, _parseInstruction(token));
        }
      }
      final interpreter = RobotInterpreter(level: level, program: program);
      expect(interpreter.runToCompletion(), RunStatus.success);
      expect(interpreter.stepsExecuted, result['steps'],
          reason: 'step count must match the solver exactly');
    });
  }
}
