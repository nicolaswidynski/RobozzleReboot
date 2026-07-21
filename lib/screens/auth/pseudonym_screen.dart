import 'package:flutter/material.dart';

import '../../data/auth_manager.dart';
import '../../theme/app_colors.dart';

/// Shown once, right after a brand-new account is created via Sign in with
/// Apple, so the player has a display name for the Leaderboard.
class PseudonymScreen extends StatefulWidget {
  const PseudonymScreen({super.key});

  @override
  State<PseudonymScreen> createState() => _PseudonymScreenState();
}

class _PseudonymScreenState extends State<PseudonymScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _loading = false;
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _isValid {
    final trimmed = _controller.text.trim();
    return trimmed.length >= 3 && trimmed.length <= 20;
  }

  Future<void> _submit() async {
    if (!_isValid) return;
    setState(() {
      _loading = true;
      _errorText = null;
    });
    try {
      await AuthManager.instance.setPseudonym(_controller.text.trim());
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on PseudonymTakenError {
      setState(() => _errorText = 'That pseudonym is already taken. Try another one.');
    } catch (e) {
      setState(() => _errorText = 'Could not save your pseudonym. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.badge_rounded, color: AppColors.accent, size: 56),
              const SizedBox(height: 20),
              const Text(
                'Choose a pseudonym',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'This is the name other players will see on the Leaderboard.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 28),
              TextField(
                controller: _controller,
                autofocus: true,
                maxLength: 20,
                textAlign: TextAlign.center,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(color: Colors.white, fontSize: 18),
                decoration: InputDecoration(
                  hintText: 'Pseudonym',
                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
                  counterStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
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
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: (_isValid && !_loading) ? _submit : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'Continue',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                ),
              ),
              if (_errorText != null) ...[
                const SizedBox(height: 16),
                Text(
                  _errorText!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
