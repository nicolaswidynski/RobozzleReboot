import 'package:flutter/material.dart';

import '../../data/auth_manager.dart';
import '../../data/custom_puzzle_store.dart';
import '../../data/robozzle_api_client.dart';
import '../../models/level.dart';
import '../../theme/app_colors.dart';
import '../game_screen.dart';
import 'editor_screen.dart';

/// Entry point for "Editor" on the landing page: lists the player's own
/// custom puzzles (each already proven solvable before it could be saved —
/// see EditorScreen/EditorTestScreen), lets them play, edit, delete, or
/// publish one, and start a new one.
class EditorHomeScreen extends StatefulWidget {
  const EditorHomeScreen({super.key});

  @override
  State<EditorHomeScreen> createState() => _EditorHomeScreenState();
}

class _EditorHomeScreenState extends State<EditorHomeScreen> {
  late Future<List<Level>> _puzzlesFuture = CustomPuzzleStore().loadAll();
  Set<String> _publishedIds = const {};
  final Set<String> _publishing = {};

  @override
  void initState() {
    super.initState();
    _loadPublishedIds();
  }

  Future<void> _loadPublishedIds() async {
    final ids = await CustomPuzzleStore().loadPublishedIds();
    if (mounted) setState(() => _publishedIds = ids);
  }

  void _reload() {
    setState(() {
      _puzzlesFuture = CustomPuzzleStore().loadAll();
    });
    _loadPublishedIds();
  }

  Future<void> _createNew() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const EditorScreen()),
    );
    if (saved == true) _reload();
  }

  Future<void> _edit(Level level) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => EditorScreen(existing: level)),
    );
    if (saved == true) _reload();
  }

  Future<void> _play(Level level) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GameScreen(levels: [level]),
      ),
    );
  }

  Future<void> _delete(Level level) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.panel,
        title: const Text('Delete puzzle?',
            style: TextStyle(color: Colors.white)),
        content: Text('"${level.name}" will be deleted permanently.',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.7))),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await CustomPuzzleStore().delete(level.id);
    _reload();
  }

  Future<void> _publish(Level level) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.panel,
        title: const Text('Publish this puzzle?',
            style: TextStyle(color: Colors.white)),
        content: Text(
          'Once published, other players will be able to see and play '
          '"${level.name}". This can\'t be undone.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Publish'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    if (!AuthManager.instance.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to publish.')),
      );
      return;
    }

    setState(() => _publishing.add(level.id));
    try {
      final (_, statusCode) = await RobozzleApiClient.instance.publishPuzzle(
        title: level.name,
        startRow: level.startRow,
        startCol: level.startCol,
        startDirection: level.startDirection.name,
        allowedCommands: level.allowedCommandsBitmask,
        slotsPerFunction: level.slotsPerFunction,
        rows: level.rowStrings,
        difficulty: level.difficulty,
      );
      if (statusCode == 200) {
        await CustomPuzzleStore().markPublished(level.id);
        if (!mounted) return;
        setState(() => _publishedIds = {..._publishedIds, level.id});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Published!')),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not publish. Please try again.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Could not publish. Check your connection.')),
        );
      }
    } finally {
      if (mounted) setState(() => _publishing.remove(level.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (Navigator.of(context).canPop())
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: InkWell(
                        onTap: () => Navigator.of(context).pop(),
                        customBorder: const CircleBorder(),
                        child: const Padding(
                          padding: EdgeInsets.all(6),
                          child: Icon(Icons.arrow_back_rounded,
                              color: Colors.white70, size: 24),
                        ),
                      ),
                    ),
                  const Text(
                    'Editor',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 26,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Design puzzles and prove they can be solved',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _createNew,
                  icon: const Icon(Icons.add_rounded, color: Colors.white),
                  label: const Text('New Puzzle',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Expanded(
                child: FutureBuilder<List<Level>>(
                  future: _puzzlesFuture,
                  builder: (context, snapshot) {
                    final puzzles = snapshot.data;
                    if (puzzles == null) {
                      return const Center(
                        child: CircularProgressIndicator(color: AppColors.accent),
                      );
                    }
                    if (puzzles.isEmpty) {
                      return Center(
                        child: Text(
                          "You haven't made any puzzles yet.",
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                        ),
                      );
                    }
                    return ListView.separated(
                      itemCount: puzzles.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final level = puzzles[i];
                        return _CustomPuzzleCard(
                          level: level,
                          published: _publishedIds.contains(level.id),
                          publishing: _publishing.contains(level.id),
                          onPlay: () => _play(level),
                          onEdit: () => _edit(level),
                          onDelete: () => _delete(level),
                          onPublish: () => _publish(level),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CustomPuzzleCard extends StatelessWidget {
  final Level level;
  final bool published;
  final bool publishing;
  final VoidCallback onPlay;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onPublish;

  const _CustomPuzzleCard({
    required this.level,
    required this.published,
    required this.publishing,
    required this.onPlay,
    required this.onEdit,
    required this.onDelete,
    required this.onPublish,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPlay,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.panelBorder),
        ),
        child: Row(
          children: [
            const Icon(Icons.extension_rounded, color: AppColors.accent, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                level.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ),
            if (published)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Icon(Icons.cloud_done_rounded,
                    color: AppColors.success, size: 20),
              )
            else if (publishing)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.accent),
                ),
              )
            else
              IconButton(
                onPressed: onPublish,
                icon: Icon(Icons.cloud_upload_rounded,
                    color: Colors.white.withValues(alpha: 0.6)),
                tooltip: 'Publish',
              ),
            IconButton(
              onPressed: onEdit,
              icon: Icon(Icons.edit_rounded, color: Colors.white.withValues(alpha: 0.6)),
              tooltip: 'Edit',
            ),
            IconButton(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
              tooltip: 'Delete',
            ),
          ],
        ),
      ),
    );
  }
}
