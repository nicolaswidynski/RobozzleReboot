/// The four directions the robot can face, in clockwise order.
enum Direction { up, right, down, left }

extension DirectionMoves on Direction {
  /// Row/column delta when moving one tile forward while facing this
  /// direction. Row 0 is the top of the grid.
  (int dRow, int dCol) get delta {
    switch (this) {
      case Direction.up:
        return (-1, 0);
      case Direction.right:
        return (0, 1);
      case Direction.down:
        return (1, 0);
      case Direction.left:
        return (0, -1);
    }
  }

  Direction turnLeft() => Direction.values[(index + 3) % 4];

  Direction turnRight() => Direction.values[(index + 1) % 4];

  /// Rotation to apply to an "up-facing" sprite so it points this way.
  double get radians {
    switch (this) {
      case Direction.up:
        return 0;
      case Direction.right:
        return 1.5707963267948966; // pi/2
      case Direction.down:
        return 3.141592653589793; // pi
      case Direction.left:
        return 4.71238898038469; // 3pi/2
    }
  }
}
