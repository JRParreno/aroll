import 'package:aroll_mobile/presentation/auth/aroll_splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

abstract final class _LandingColors {
  static const navy = kAuthNavyBackground;
  static const navyDark = Color(0xFF1E3A5F);
  static const softBlue = kAuthSoftBlue;
  static const textOnNavy = Colors.white;
  static const textMuted = kAuthMutedOnNavy;
  static const outline = Color(0x66FFFFFF);
}

class RoleLandingScreen extends StatefulWidget {
  const RoleLandingScreen({super.key});

  @override
  State<RoleLandingScreen> createState() => _RoleLandingScreenState();
}

class _RoleLandingScreenState extends State<RoleLandingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _intro;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );
    _fade = CurvedAnimation(parent: _intro, curve: Curves.easeOut);
    _intro.forward();
  }

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _LandingColors.navy,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fade,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight,
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Image.asset(
                          'assets/branding/logo.png',
                          height: 150,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                        ),
                        const SizedBox(height: 36),
                        const Text(
                          'Welcome to Aroll+',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _LandingColors.textOnNavy,
                            fontSize: 24,
                            fontWeight: FontWeight.w600,
                            height: 1.25,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Choose how you want to continue.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _LandingColors.textMuted,
                            fontSize: 15,
                            fontWeight: FontWeight.w400,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 40),
                        _LoginButton(
                          icon: Icons.badge_outlined,
                          label: 'Login as Employee',
                          filled: true,
                          onTap: () => context.go('/login/employee'),
                        ),
                        const SizedBox(height: 14),
                        _LoginButton(
                          icon: Icons.business_center_outlined,
                          label: 'Login as Business Owner',
                          filled: false,
                          onTap: () => context.go('/login/owner-options'),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _LoginButton extends StatefulWidget {
  const _LoginButton({
    required this.icon,
    required this.label,
    required this.filled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool filled;
  final VoidCallback onTap;

  @override
  State<_LoginButton> createState() => _LoginButtonState();
}

class _LoginButtonState extends State<_LoginButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final filled = widget.filled;

    return AnimatedScale(
      scale: _pressed ? 0.98 : 1,
      duration: const Duration(milliseconds: 110),
      curve: Curves.easeOut,
      child: Material(
        color: filled ? _LandingColors.softBlue : Colors.transparent,
        elevation: filled ? 2 : 0,
        shadowColor: Colors.black26,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: widget.onTap,
          onHighlightChanged: (value) => setState(() => _pressed = value),
          borderRadius: BorderRadius.circular(20),
          splashColor: filled
              ? _LandingColors.navyDark.withValues(alpha: 0.08)
              : Colors.white.withValues(alpha: 0.12),
          child: Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: filled
                  ? null
                  : Border.all(color: _LandingColors.outline, width: 1.4),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  widget.icon,
                  size: 22,
                  color: filled ? _LandingColors.navyDark : Colors.white,
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: filled ? _LandingColors.navyDark : Colors.white,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.1,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class OwnerOptionsScreen extends StatelessWidget {
  const OwnerOptionsScreen({super.key});

  static const _bg = kAuthNavyBackground;
  static const _navy = Color(0xFF1E3A5F);
  static const _softBlue = kAuthSoftBlue;
  static const _softBlueSurface = Color(0xFFEAF2FB);
  static const _textOnNavy = Colors.white;
  static const _textMuted = kAuthMutedOnNavy;
  static const _border = Color(0xFFE5E7EB);
  static const _cardTitle = Color(0xFF111827);
  static const _cardSubtitle = Color(0xFF6B7280);

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: _softBlue,
          primary: _navy,
          secondary: _softBlue,
          surface: Colors.white,
          brightness: Brightness.light,
        ),
      ),
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: _bg,
          elevation: 0,
          scrolledUnderElevation: 0,
          foregroundColor: _textOnNavy,
          automaticallyImplyLeading: false,
          leading: IconButton(
            tooltip: 'Back',
            onPressed: () => context.go('/login'),
            icon: const Icon(Icons.arrow_back_rounded, color: _textOnNavy),
          ),
          titleSpacing: 0,
          title: const Text(
            'Business Owner',
            style: TextStyle(
              color: _textOnNavy,
              fontSize: 20,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
            ),
          ),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
            children: [
              const Text(
                'Manage your business from anywhere',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _textMuted,
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 28),
              _OptionCard(
                icon: Icons.login_rounded,
                title: 'Sign In',
                subtitle: 'Use your business code and owner account.',
                onTap: () => context.go('/login/owner'),
              ),
              _OptionCard(
                icon: Icons.add_business_rounded,
                title: 'Register Business',
                subtitle: 'Submit your business details and requirements.',
                onTap: () => context.go('/register-business'),
              ),
              _OptionCard(
                icon: Icons.manage_search_rounded,
                title: 'Track Registration Status',
                subtitle: 'Check an existing application using your email.',
                onTap: () => context.go('/track-registration'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white,
        elevation: 0.5,
        shadowColor: OwnerOptionsScreen._navy.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          splashColor: OwnerOptionsScreen._softBlue.withValues(alpha: 0.25),
          highlightColor: OwnerOptionsScreen._softBlueSurface,
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: OwnerOptionsScreen._border),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: OwnerOptionsScreen._softBlueSurface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    color: OwnerOptionsScreen._navy,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: OwnerOptionsScreen._cardTitle,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: OwnerOptionsScreen._cardSubtitle,
                          fontSize: 13,
                          height: 1.35,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: OwnerOptionsScreen._cardSubtitle,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
