import 'package:flutter/material.dart';

/// Shared auth-flow background (Employee Login / Role Landing / Splash).
const Color kAuthNavyBackground = Color(0xFF1E466E);
const Color kAuthSoftBlue = Color(0xFFB9D8EE);
const Color kAuthMutedOnNavy = Color(0xFFC8D8E7);

/// Minimal splash shown while the session is restored. UI only — duration is
/// driven by existing restore logic in [ArollApp].
class ArollSplashScreen extends StatefulWidget {
  const ArollSplashScreen({super.key});

  @override
  State<ArollSplashScreen> createState() => _ArollSplashScreenState();
}

class _ArollSplashScreenState extends State<ArollSplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    final curve = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _fade = curve;
    _scale = Tween<double>(begin: 0.92, end: 1).animate(curve);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kAuthNavyBackground,
      body: SafeArea(
        child: Center(
          child: FadeTransition(
            opacity: _fade,
            child: ScaleTransition(
              scale: _scale,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/branding/logo.png',
                    height: 140,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                  ),
                  const SizedBox(height: 28),
                  const Text(
                    'Preparing your workspace…',
                    style: TextStyle(
                      color: kAuthMutedOnNavy,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: kAuthSoftBlue,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
