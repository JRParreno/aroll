import 'package:aroll_mobile/core/theme/business_brand_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

/// Shared visual tokens for Employee and Owner mobile portals.
abstract final class AppColors {
  static const scaffold = Color(0xFFF4F6F8);
  static const primary = Color(0xFF1E466E);
  static const primaryDark = Color(0xFF1E3A5F);
  static const border = Color(0xFFE5E7EB);
  static const textPrimary = Color(0xFF111827);
  static const textBody = Color(0xFF374151);
  static const textMuted = Color(0xFF6B7280);
  static const iconWell = Color(0xFFE7EEF5);
  static const fieldFill = Color(0xFFF9FAFB);
  static const chipFill = Color(0xFFF3F4F6);
  static const success = Color(0xFF16A34A);
  static const warning = Color(0xFFD97706);
  static const danger = Color(0xFFDC2626);
  static const white = Colors.white;
}

abstract final class AppRadii {
  static const card = 18.0;
  static const button = 14.0;
  static const input = 12.0;
  static const chip = 999.0;
  static const sheet = 20.0;
}

abstract final class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

abstract final class AppSizes {
  static const buttonHeight = 48.0;
  static const iconSm = 18.0;
  static const iconMd = 22.0;
  static const iconLg = 24.0;
  static const iconXl = 28.0;
  static const emptyIcon = 44.0;
  static const minTap = 48.0;
  static const navHeight = 68.0;
}

TextStyle appPageTitleStyle([Color? color]) => TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.w700,
      height: 1.27,
      color: color ?? AppColors.textPrimary,
    );

TextStyle appSectionTitleStyle([Color? color]) => TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w700,
      color: color ?? AppColors.textPrimary,
    );

TextStyle appBodyStyle([Color? color]) => TextStyle(
      fontSize: 14,
      height: 1.4,
      color: color ?? AppColors.textBody,
    );

TextStyle appMutedStyle([Color? color]) => TextStyle(
      fontSize: 13,
      height: 1.35,
      color: color ?? AppColors.textMuted,
    );

List<BoxShadow> get appCardShadow => [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.035),
        blurRadius: 14,
        offset: const Offset(0, 7),
      ),
    ];

Decoration appCardDecoration({Color? color}) => BoxDecoration(
      color: color ?? AppColors.white,
      borderRadius: BorderRadius.circular(AppRadii.card),
      border: Border.all(color: AppColors.border),
      boxShadow: appCardShadow,
    );

ButtonStyle appPrimaryButtonStyle({Color? background}) =>
    FilledButton.styleFrom(
      backgroundColor: background ?? AppColors.primaryDark,
      foregroundColor: AppColors.white,
      disabledBackgroundColor:
          (background ?? AppColors.primaryDark).withValues(alpha: 0.6),
      minimumSize: const Size(double.infinity, AppSizes.buttonHeight),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.button),
      ),
      elevation: 0,
      textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
    );

ButtonStyle appBrandedPrimaryButtonStyle(
  BuildContext context, {
  Color? background,
}) {
  final brand = BrandColors.of(context);
  return appPrimaryButtonStyle(background: background ?? brand.button);
}

ButtonStyle appSecondaryButtonStyle() => OutlinedButton.styleFrom(
      foregroundColor: AppColors.textBody,
      side: const BorderSide(color: AppColors.border),
      minimumSize: const Size(double.infinity, AppSizes.buttonHeight),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.button),
      ),
      textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
    );

InputDecoration appInputDecoration({
  String? hintText,
  String? labelText,
  Widget? prefixIcon,
  Widget? suffixIcon,
}) {
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppRadii.input),
    borderSide: const BorderSide(color: AppColors.border),
  );
  return InputDecoration(
    labelText: labelText,
    hintText: hintText,
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    filled: true,
    fillColor: AppColors.fieldFill,
    isDense: true,
    contentPadding:
        const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: border,
    enabledBorder: border,
    focusedBorder: border.copyWith(
      borderSide: const BorderSide(color: AppColors.primaryDark, width: 1.5),
    ),
  );
}

InputDecoration appBrandedInputDecoration(
  BuildContext context, {
  String? hintText,
  String? labelText,
  Widget? prefixIcon,
  Widget? suffixIcon,
}) {
  final brand = BrandColors.of(context);
  final base = appInputDecoration(
    hintText: hintText,
    labelText: labelText,
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
  );
  return base.copyWith(
    focusedBorder: (base.enabledBorder as OutlineInputBorder?)?.copyWith(
      borderSide: BorderSide(color: brand.primary, width: 1.5),
    ),
  );
}

/// Fade + slight slide page transition for GoRouter routes.
CustomTransitionPage<T> appFadeSlidePage<T>({
  required LocalKey key,
  required Widget child,
  String? name,
}) {
  return CustomTransitionPage<T>(
    key: key,
    name: name,
    child: child,
    transitionDuration: const Duration(milliseconds: 240),
    reverseTransitionDuration: const Duration(milliseconds: 200),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.02, 0.01),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// Soft press scale used for buttons and tappable cards.
class AppPressable extends StatefulWidget {
  const AppPressable({
    super.key,
    required this.child,
    this.onTap,
    this.borderRadius,
    this.enabled = true,
    this.scale = 0.985,
  });

  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius? borderRadius;
  final bool enabled;
  final double scale;

  @override
  State<AppPressable> createState() => _AppPressableState();
}

class _AppPressableState extends State<AppPressable> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final radius =
        widget.borderRadius ?? BorderRadius.circular(AppRadii.card);
    return AnimatedScale(
      scale: _pressed && widget.enabled ? widget.scale : 1,
      duration: const Duration(milliseconds: 90),
      curve: Curves.easeOut,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: radius,
          onTap: widget.enabled ? widget.onTap : null,
          onHighlightChanged: (value) {
            if (!widget.enabled) return;
            setState(() => _pressed = value);
          },
          child: widget.child,
        ),
      ),
    );
  }
}

class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.margin,
    this.onTap,
  });

  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets? margin;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      width: double.infinity,
      margin: margin,
      padding: padding,
      decoration: appCardDecoration(),
      child: child,
    );
    if (onTap == null) return card;
    return AppPressable(
      onTap: onTap,
      child: card,
    );
  }
}

class AppPrimaryButton extends StatelessWidget {
  const AppPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.icon,
    this.backgroundColor,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: AppSizes.buttonHeight,
      child: FilledButton(
        onPressed: loading ? null : onPressed,
        style: appBrandedPrimaryButtonStyle(
          context,
          background: backgroundColor,
        ),
        child: loading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.white,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(label),
                  if (icon != null) ...[
                    const SizedBox(width: 8),
                    Icon(icon, size: AppSizes.iconSm),
                  ],
                ],
              ),
      ),
    );
  }
}

class AppOutlinedButton extends StatelessWidget {
  const AppOutlinedButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: AppSizes.buttonHeight,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon ?? Icons.logout_rounded, size: AppSizes.iconSm),
        label: Text(label),
        style: appSecondaryButtonStyle(),
      ),
    );
  }
}

class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.title,
    this.description,
    this.icon = Icons.inbox_outlined,
    this.inCard = false,
    this.action,
  });

  final String title;
  final String? description;
  final IconData icon;
  final bool inCard;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 72,
          width: 72,
          decoration: BoxDecoration(
            color: BrandColors.of(context).iconWell,
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            size: AppSizes.emptyIcon,
            color: BrandColors.of(context).primary,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          title,
          textAlign: TextAlign.center,
          style: appSectionTitleStyle(),
        ),
        if (description != null) ...[
          const SizedBox(height: 6),
          Text(
            description!,
            textAlign: TextAlign.center,
            style: appMutedStyle(),
          ),
        ],
        if (action != null) ...[
          const SizedBox(height: AppSpacing.lg),
          action!,
        ],
      ],
    );

    if (inCard) {
      return AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
        child: content,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Center(child: content),
    );
  }
}

class AppErrorState extends StatelessWidget {
  const AppErrorState({
    super.key,
    this.message = 'Something went wrong. Please try again.',
    this.onRetry,
  });

  final String message;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 40,
              color: AppColors.textMuted,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              message,
              textAlign: TextAlign.center,
              style: appBodyStyle(),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.md),
              TextButton(
                onPressed: () {
                  onRetry!();
                },
                child: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Shimmer-style skeleton block.
class AppSkeleton extends StatefulWidget {
  const AppSkeleton({
    super.key,
    this.height = 16,
    this.width,
    this.radius = 10,
  });

  final double height;
  final double? width;
  final double radius;

  @override
  State<AppSkeleton> createState() => _AppSkeletonState();
}

class _AppSkeletonState extends State<AppSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        final shade = Color.lerp(
          const Color(0xFFE5E7EB),
          const Color(0xFFF3F4F6),
          (t < 0.5 ? t * 2 : (1 - t) * 2),
        )!;
        return Container(
          height: widget.height,
          width: widget.width,
          decoration: BoxDecoration(
            color: shade,
            borderRadius: BorderRadius.circular(widget.radius),
          ),
        );
      },
    );
  }
}

class AppSkeletonCard extends StatelessWidget {
  const AppSkeletonCard({super.key, this.lines = 3});

  final int lines;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSkeleton(height: 18, width: 140),
          const SizedBox(height: 12),
          for (var i = 0; i < lines; i++) ...[
            AppSkeleton(
              height: 12,
              width: i == lines - 1 ? 160 : double.infinity,
            ),
            if (i != lines - 1) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

/// Full-page skeleton used instead of blank white / bare spinner.
class AppPageSkeleton extends StatelessWidget {
  const AppPageSkeleton({
    super.key,
    this.cardCount = 3,
    this.showHeader = true,
  });

  final int cardCount;
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        if (showHeader) ...[
          const AppSkeleton(height: 22, width: 180),
          const SizedBox(height: 8),
          const AppSkeleton(height: 12, width: 220),
          const SizedBox(height: 18),
        ],
        for (var i = 0; i < cardCount; i++) ...[
          AppSkeletonCard(lines: 2 + (i % 2)),
          if (i != cardCount - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }
}

Widget appLoadingView({int cardCount = 3}) =>
    AppPageSkeleton(cardCount: cardCount);

Future<void> showAppFeedback(
  BuildContext context, {
  required String title,
  String? message,
  required bool success,
  String actionLabel = 'Done',
}) {
  final color = success ? AppColors.success : AppColors.danger;
  final icon =
      success ? Icons.check_circle_rounded : Icons.error_outline_rounded;

  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: title,
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, animation, secondaryAnimation) {
      return Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: MediaQuery.sizeOf(context).width - 64,
            constraints: const BoxConstraints(maxWidth: 360),
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(AppRadii.card),
              boxShadow: appCardShadow,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ScaleTransition(
                  scale: CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutBack,
                  ),
                  child: Container(
                    height: 64,
                    width: 64,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: 34, color: color),
                  ),
                ),
                const SizedBox(height: 14),
                Text(title, textAlign: TextAlign.center, style: appSectionTitleStyle()),
                if (message != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: appMutedStyle(),
                  ),
                ],
                const SizedBox(height: 18),
                AppPrimaryButton(
                  label: actionLabel,
                  onPressed: () => Navigator.of(context).pop(),
                  backgroundColor: color,
                ),
              ],
            ),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          ),
          child: child,
        ),
      );
    },
  );
}

void showAppSnack(
  BuildContext context, {
  required String message,
  bool isError = false,
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: isError ? AppColors.danger : AppColors.primaryDark,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.button),
      ),
      content: Text(message),
    ),
  );
}

/// Soft system haptic for primary actions (no-op if unsupported).
Future<void> appLightHaptic() async {
  try {
    await HapticFeedback.lightImpact();
  } catch (_) {}
}

/// Navigate back helper used by shared scaffolds.
void appNavigateBack(BuildContext context, {required String fallbackRoute}) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go(fallbackRoute);
  }
}
