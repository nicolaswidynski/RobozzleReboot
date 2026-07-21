import 'package:flutter/material.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../data/auth_manager.dart';
import '../../theme/app_colors.dart';

/// Gate shown before Leaderboard/Editor: sign in with Apple, then hand back
/// whether the resulting account is brand-new (caller decides whether to
/// continue to a pseudonym screen).
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  bool _loading = false;
  String? _errorText;

  Future<void> _signIn() async {
    setState(() {
      _loading = true;
      _errorText = null;
    });
    try {
      final outcome = await AuthManager.instance.signInWithApple();
      if (!mounted) return;
      Navigator.of(context).pop(outcome);
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        // User dismissed the sheet — no error, just stay on this screen.
        return;
      }
      setState(() => _errorText = 'Sign in with Apple failed. Please try again.');
    } catch (e) {
      setState(() => _errorText = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.person_rounded, color: AppColors.accent, size: 56),
              const SizedBox(height: 20),
              const Text(
                'Sign in required',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Sign in with Apple to pick a pseudonym and unlock this feature.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 32),
              if (_loading)
                const CircularProgressIndicator(color: AppColors.accent)
              else
                SignInWithAppleButton(
                  onPressed: _signIn,
                  style: SignInWithAppleButtonStyle.white,
                  borderRadius: BorderRadius.circular(10),
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
