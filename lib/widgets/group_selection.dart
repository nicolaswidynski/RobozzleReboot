/// Mutable holder passed as a [Draggable]'s `data` for a grouped palette
/// button (colors/paint/calls collapsed into one button with a fan-out
/// menu) — the concrete instruction/color isn't known until partway through
/// the drag, once the player's finger has swept past the revealed menu, but
/// `Draggable.data` is fixed at drag-start. Mutating [value] mid-drag and
/// having the matching `DragTarget<GroupSelection<T>>` read it at drop time
/// (instead of at drag-start) is what makes that work.
class GroupSelection<T> {
  T? value;
}
