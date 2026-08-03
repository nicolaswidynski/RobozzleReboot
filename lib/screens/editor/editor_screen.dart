import 'package:flutter/material.dart' hide GridTile;

import '../../data/custom_puzzle_store.dart';
import '../../data/editor_draft_store.dart';
import '../../data/program_store.dart';
import '../../models/direction.dart';
import '../../models/grid_tile.dart';
import '../../models/level.dart';
import '../../models/program.dart';
import '../../models/tile_color.dart';
import '../../theme/app_colors.dart';
import '../../widgets/tile_color_ui.dart';
import 'editor_grid.dart';
import 'editor_test_screen.dart';

enum _EditorTool { paintRed, paintGreen, paintBlue, star, gap, start }

/// Builds (or edits) a custom puzzle: grid, start state, function slot
/// budgets, and allowed paint colors. Saving requires proving the puzzle is
/// solvable first — "Test Solution" opens [EditorTestScreen], and only a
/// successful solve there (accepted by the author) actually persists it via
/// [CustomPuzzleStore].
///
/// For a brand-new (not-yet-accepted) puzzle, the in-progress draft is also
/// persisted via [EditorDraftStore] whenever this screen closes without
/// being accepted, so navigating away and coming back later resumes where
/// the player left off. The Reset button clears that draft (or, when
/// editing an already-saved puzzle, discards in-progress edits back to the
/// last saved version).
class EditorScreen extends StatefulWidget {
  /// When editing an already-saved puzzle; `null` starts a blank one.
  final Level? existing;

  const EditorScreen({super.key, this.existing});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  static const int _defaultRows = 6;
  static const int _defaultCols = 6;
  static const int _minSize = 1;
  static const int _maxSize = 14;
  static const int _maxSlotsPerFunction = 12;

  final TextEditingController _titleController = TextEditingController();
  late List<List<GridTile?>> _grid;
  late int _startRow;
  late int _startCol;
  late Direction _startDirection;
  late List<int> _slotsPerFunction;
  late Set<TileColor> _allowedPaintColors;
  late int _suggestedDifficulty;
  _EditorTool _tool = _EditorTool.paintRed;
  bool _saving = false;

  /// True once a puzzle has actually been solved and locally saved (see
  /// [_testSolution]) — suppresses the draft auto-save on exit, since at
  /// that point there's nothing left to resume.
  bool _accepted = false;

  int get _rowCount => _grid.length;
  int get _colCount => _grid.isEmpty ? 0 : _grid[0].length;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _applyExistingState(existing);
    } else {
      _applyBlankState();
      _restoreDraftIfAny();
    }
  }

  @override
  void dispose() {
    if (widget.existing == null && !_accepted) {
      // Fire-and-forget: _draftJson() reads _titleController synchronously
      // before it's disposed below, so the controller isn't touched by the
      // time the async save actually runs.
      EditorDraftStore().save(_draftJson());
    }
    _titleController.dispose();
    super.dispose();
  }

  void _applyExistingState(Level existing) {
    _titleController.text = existing.name;
    _grid = _cloneGrid(existing.grid);
    _startRow = existing.startRow;
    _startCol = existing.startCol;
    _startDirection = existing.startDirection;
    _slotsPerFunction = List.of(existing.slotsPerFunction);
    _allowedPaintColors = Set.of(existing.allowedPaintColors);
    _suggestedDifficulty = existing.difficultyStars;
  }

  void _applyBlankState() {
    _titleController.text = '';
    _grid = List.generate(
      _defaultRows,
      (_) => List<GridTile?>.filled(_defaultCols, null, growable: true),
      growable: true,
    );
    _startRow = 0;
    _startCol = 0;
    _startDirection = Direction.right;
    _slotsPerFunction = [5, 0, 0, 0, 0];
    _allowedPaintColors = {TileColor.red, TileColor.green, TileColor.blue};
    _suggestedDifficulty = 1;
  }

  Future<void> _restoreDraftIfAny() async {
    final draft = await EditorDraftStore().load();
    if (draft == null || !mounted) return;
    final level = Level.fromJson(draft, idPrefix: 'draft');
    setState(() {
      _titleController.text = level.name;
      _grid = _cloneGrid(level.grid);
      _startRow = level.startRow;
      _startCol = level.startCol;
      _startDirection = level.startDirection;
      _slotsPerFunction = List.of(level.slotsPerFunction);
      _allowedPaintColors = Set.of(level.allowedPaintColors);
      _suggestedDifficulty = level.difficultyStars;
    });
  }

  /// Same JSON shape as the bundled catalog (see [Level.fromJson]) so
  /// [_restoreDraftIfAny] can parse it with the exact same code.
  Map<String, dynamic> _draftJson() {
    final level = Level(
      id: 'draft',
      name: _titleController.text,
      grid: _grid,
      startRow: _startRow,
      startCol: _startCol,
      startDirection: _startDirection,
      slotsPerFunction: _slotsPerFunction,
      allowedPaintColors: _allowedPaintColors,
      difficulty: _suggestedDifficulty.toDouble(),
    );
    return {
      'sourceId': 'draft',
      'title': level.name,
      'author': '',
      'difficulty': level.difficulty,
      'popularity': 0,
      'startRow': level.startRow,
      'startCol': level.startCol,
      'startDirection': level.startDirection.name,
      'allowedCommands': level.allowedCommandsBitmask,
      'slotsPerFunction': level.slotsPerFunction,
      'rows': level.rowStrings,
    };
  }

  Future<void> _confirmReset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.panel,
        title:
            const Text('Reset this puzzle?', style: TextStyle(color: Colors.white)),
        content: Text(
          widget.existing == null
              ? 'All progress on this puzzle will be cleared.'
              : 'Unsaved changes will be discarded, back to the last saved '
                  'version.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Reset', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      final existing = widget.existing;
      if (existing != null) {
        _applyExistingState(existing);
      } else {
        _applyBlankState();
      }
      _tool = _EditorTool.paintRed;
    });

    if (widget.existing == null) {
      await EditorDraftStore().clear();
    }
  }

  List<List<GridTile?>> _cloneGrid(List<List<GridTile?>> source) => [
        for (final row in source)
          [for (final tile in row) tile?.copyWith()],
      ];

  void _onCellTap(int row, int col) {
    final current = _grid[row][col];
    setState(() {
      switch (_tool) {
        case _EditorTool.gap:
          _grid[row][col] = null;
        case _EditorTool.paintRed:
          _grid[row][col] =
              GridTile(color: TileColor.red, hasStar: current?.hasStar ?? false);
        case _EditorTool.paintGreen:
          _grid[row][col] = GridTile(
              color: TileColor.green, hasStar: current?.hasStar ?? false);
        case _EditorTool.paintBlue:
          _grid[row][col] = GridTile(
              color: TileColor.blue, hasStar: current?.hasStar ?? false);
        case _EditorTool.star:
          if (current != null) {
            _grid[row][col] = current.copyWith(hasStar: !current.hasStar);
          }
        case _EditorTool.start:
          if (current != null) {
            _startRow = row;
            _startCol = col;
          }
      }
    });
  }

  void _rotateStart() {
    setState(() => _startDirection = _startDirection.turnRight());
  }

  String _directionLabel(Direction direction) {
    switch (direction) {
      case Direction.up:
        return 'Up';
      case Direction.right:
        return 'Right';
      case Direction.down:
        return 'Down';
      case Direction.left:
        return 'Left';
    }
  }

  void _clampStart() {
    if (_startRow >= _rowCount) _startRow = _rowCount - 1;
    if (_startCol >= _colCount) _startCol = _colCount - 1;
  }

  void _addRow() {
    if (_rowCount >= _maxSize) return;
    setState(() =>
        _grid.add(List<GridTile?>.filled(_colCount, null, growable: true)));
  }

  void _removeRow() {
    if (_rowCount <= _minSize) return;
    // A 1-row (or 1-column) corridor is a fine puzzle shape, but 1x1 is a
    // single tile with nowhere to move — refuse the removal that would
    // leave both dimensions at 1 instead of just the one being shrunk.
    if (_rowCount - 1 <= _minSize && _colCount <= _minSize) return;
    setState(() {
      _grid.removeLast();
      _clampStart();
    });
  }

  void _addCol() {
    if (_colCount >= _maxSize) return;
    setState(() {
      for (final row in _grid) {
        row.add(null);
      }
    });
  }

  void _removeCol() {
    if (_colCount <= _minSize) return;
    if (_colCount - 1 <= _minSize && _rowCount <= _minSize) return;
    setState(() {
      for (final row in _grid) {
        row.removeLast();
      }
      _clampStart();
    });
  }

  void _setSlotCount(int functionIndex, int delta) {
    setState(() {
      final next =
          (_slotsPerFunction[functionIndex] + delta).clamp(0, _maxSlotsPerFunction);
      _slotsPerFunction[functionIndex] = next;
    });
  }

  void _toggleAllowedColor(TileColor color) {
    setState(() {
      if (_allowedPaintColors.contains(color)) {
        _allowedPaintColors.remove(color);
      } else {
        _allowedPaintColors.add(color);
      }
    });
  }

  void _setSuggestedDifficulty(int value) {
    setState(() => _suggestedDifficulty = value);
  }

  String? get _validationError {
    if (_titleController.text.trim().isEmpty) {
      return 'Give your puzzle a title first.';
    }
    final starCount =
        _grid.fold(0, (n, row) => n + row.where((t) => t?.hasStar ?? false).length);
    if (starCount == 0) return 'Place at least one star.';
    // Solvable (walk off the start tile and back onto it), but a pointless
    // puzzle shape — nothing to do until the one star is un-collectable
    // except by immediately backtracking onto where the robot began.
    if (starCount == 1 && (_grid[_startRow][_startCol]?.hasStar ?? false)) {
      return "The only star can't be on the starting tile.";
    }
    if (_grid[_startRow][_startCol] == null) {
      return "The start tile can't be a gap.";
    }
    if (_slotsPerFunction[0] <= 0) {
      return 'F1 needs at least 1 slot.';
    }
    return null;
  }

  Future<void> _testSolution() async {
    final error = _validationError;
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
      return;
    }

    final draftLevel = Level(
      id: widget.existing?.id ?? CustomPuzzleStore.newId(),
      name: _titleController.text.trim(),
      grid: _cloneGrid(_grid),
      startRow: _startRow,
      startCol: _startCol,
      startDirection: _startDirection,
      slotsPerFunction: List.of(_slotsPerFunction),
      allowedPaintColors: Set.of(_allowedPaintColors),
      difficulty: _suggestedDifficulty.toDouble(),
    );

    final program = await Navigator.of(context).push<RobotProgram>(
      MaterialPageRoute(builder: (_) => EditorTestScreen(level: draftLevel)),
    );
    if (program == null || !mounted) return; // cancelled, or not solved

    setState(() => _saving = true);
    await CustomPuzzleStore().save(draftLevel);
    await ProgramStore().save(draftLevel, program);
    _accepted = true; // stops dispose() from re-saving this as a draft
    if (widget.existing == null) await EditorDraftStore().clear();

    // Local save only — publishing to the server is a separate, explicit,
    // confirmed action the player takes from EditorHomeScreen's puzzle
    // list, since it's irreversible.
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          widget.existing == null ? 'New Puzzle' : 'Edit Puzzle',
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          IconButton(
            onPressed: _confirmReset,
            icon: const Icon(Icons.restart_alt_rounded),
            tooltip: 'Reset',
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _titleController,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              decoration: InputDecoration(
                hintText: 'Puzzle title',
                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
                filled: true,
                fillColor: AppColors.panel,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.panelBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.panelBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.accent),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _SectionLabel('Grid (${_rowCount}x$_colCount)'),
            const SizedBox(height: 8),
            Row(
              children: [
                _StepperButtons(
                  label: 'Rows',
                  onAdd: _addRow,
                  onRemove: _removeRow,
                ),
                const SizedBox(width: 16),
                _StepperButtons(
                  label: 'Cols',
                  onAdd: _addCol,
                  onRemove: _removeCol,
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 320,
              child: EditorGrid(
                grid: _grid,
                startRow: _startRow,
                startCol: _startCol,
                startDirection: _startDirection,
                onCellTap: _onCellTap,
              ),
            ),
            const SizedBox(height: 12),
            const _SectionLabel('Tools'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _ToolChip(
                  label: 'Red',
                  color: TileColor.red.uiColor,
                  selected: _tool == _EditorTool.paintRed,
                  onTap: () => setState(() => _tool = _EditorTool.paintRed),
                ),
                _ToolChip(
                  label: 'Green',
                  color: TileColor.green.uiColor,
                  selected: _tool == _EditorTool.paintGreen,
                  onTap: () => setState(() => _tool = _EditorTool.paintGreen),
                ),
                _ToolChip(
                  label: 'Blue',
                  color: TileColor.blue.uiColor,
                  selected: _tool == _EditorTool.paintBlue,
                  onTap: () => setState(() => _tool = _EditorTool.paintBlue),
                ),
                _ToolChip(
                  label: 'Star',
                  icon: Icons.star_rounded,
                  selected: _tool == _EditorTool.star,
                  onTap: () => setState(() => _tool = _EditorTool.star),
                ),
                _ToolChip(
                  label: 'Gap',
                  icon: Icons.crop_square_rounded,
                  selected: _tool == _EditorTool.gap,
                  onTap: () => setState(() => _tool = _EditorTool.gap),
                ),
                _ToolChip(
                  label: 'Start',
                  icon: Icons.navigation_rounded,
                  selected: _tool == _EditorTool.start,
                  onTap: () => setState(() => _tool = _EditorTool.start),
                ),
                InkWell(
                  onTap: _rotateStart,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.panel,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.panelBorder),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.rotate_right_rounded,
                            color: Colors.white70, size: 18),
                        const SizedBox(width: 6),
                        Text(
                          'Facing ${_directionLabel(_startDirection)}',
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const _SectionLabel('Function slots'),
            const SizedBox(height: 8),
            for (var i = 0; i < 5; i++) ...[
              _SlotCountRow(
                label: 'F${i + 1}',
                count: _slotsPerFunction[i],
                onAdd: () => _setSlotCount(i, 1),
                onRemove: () => _setSlotCount(i, -1),
              ),
              const SizedBox(height: 6),
            ],
            const SizedBox(height: 12),
            const _SectionLabel('Allowed paint colors'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final color in [TileColor.red, TileColor.green, TileColor.blue])
                  _ToolChip(
                    label: color.label,
                    color: color.uiColor,
                    selected: _allowedPaintColors.contains(color),
                    onTap: () => _toggleAllowedColor(color),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            const _SectionLabel('Suggested difficulty'),
            const SizedBox(height: 8),
            Row(
              children: [
                for (var i = 1; i <= 5; i++)
                  InkWell(
                    key: ValueKey('difficulty_star_$i'),
                    onTap: () => _setSuggestedDifficulty(i),
                    customBorder: const CircleBorder(),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        _suggestedDifficulty >= i
                            ? Icons.star_rounded
                            : Icons.star_border_rounded,
                        color: AppColors.star,
                        size: 28,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _testSolution,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                  _saving ? 'Saving...' : 'Test Solution',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.6),
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _StepperButtons extends StatelessWidget {
  final String label;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  const _StepperButtons({
    required this.label,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13)),
        const SizedBox(width: 6),
        _RoundButton(icon: Icons.remove_rounded, onTap: onRemove),
        const SizedBox(width: 4),
        _RoundButton(icon: Icons.add_rounded, onTap: onAdd),
      ],
    );
  }
}

class _SlotCountRow extends StatelessWidget {
  final String label;
  final int count;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  const _SlotCountRow({
    required this.label,
    required this.count,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 32,
          child: Text(label,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
        ),
        _RoundButton(icon: Icons.remove_rounded, onTap: onRemove),
        SizedBox(
          width: 32,
          child: Text(
            '$count',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
        ),
        _RoundButton(icon: Icons.add_rounded, onTap: onAdd),
      ],
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _RoundButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: AppColors.panel,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.panelBorder),
        ),
        child: Icon(icon, color: Colors.white70, size: 16),
      ),
    );
  }
}

class _ToolChip extends StatelessWidget {
  final String label;
  final Color? color;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  const _ToolChip({
    required this.label,
    this.color,
    this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.accent : AppColors.panel,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? AppColors.accent : AppColors.panelBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (color != null) ...[
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
            ],
            if (icon != null) ...[
              Icon(icon, color: Colors.white, size: 14),
              const SizedBox(width: 6),
            ],
            Text(label,
                style: const TextStyle(color: Colors.white, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
