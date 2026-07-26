import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../data/auth_manager.dart';
import '../../theme/app_colors.dart';

/// Gate shown before Leaderboard/Editor: sign in, then hand back whether the
/// resulting account is brand-new (caller decides whether to continue to a
/// pseudonym screen).
///
/// Sign in with Apple has no Android equivalent, so it's only offered on
/// iOS/macOS — Google Sign-In is offered everywhere, and is the only option
/// on Android.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  bool _loading = false;
  String? _errorText;

  bool get _isApplePlatform =>
      !kIsWeb && (Platform.isIOS || Platform.isMacOS);

  Future<void> _signInWithApple() async {
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

  Future<void> _signInWithGoogle() async {
    setState(() {
      _loading = true;
      _errorText = null;
    });
    try {
      final outcome = await AuthManager.instance.signInWithGoogle();
      if (!mounted) return;
      Navigator.of(context).pop(outcome);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        // User dismissed the flow — no error, just stay on this screen.
        return;
      }
      setState(() => _errorText = 'Sign in with Google failed. Please try again.');
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
                'Sign in to pick a pseudonym and unlock this feature.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 32),
              if (_loading)
                const CircularProgressIndicator(color: AppColors.accent)
              else ...[
                if (_isApplePlatform) ...[
                  SignInWithAppleButton(
                    onPressed: _signInWithApple,
                    style: SignInWithAppleButtonStyle.white,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  const SizedBox(height: 12),
                ],
                _GoogleSignInButton(onPressed: _signInWithGoogle),
              ],
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

class _GoogleSignInButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _GoogleSignInButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(horizontal: 24),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.g_mobiledata_rounded, size: 28, color: Colors.black87),
            SizedBox(width: 2),
            Text(
              'Sign in with Google',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }
}
