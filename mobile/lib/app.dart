import 'package:aroll_mobile/core/app_state.dart';
import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/core/router/app_router.dart';
import 'package:aroll_mobile/domain/usecase/auth/restore_session_usecase.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class ArollApp extends StatefulWidget {
  const ArollApp({super.key});

  @override
  State<ArollApp> createState() => _ArollAppState();
}

class _ArollAppState extends State<ArollApp> {
  late final AppState _appState = sl<AppState>();
  GoRouter? _router;
  bool _restoring = true;

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    await sl<RestoreSessionUsecase>()();
    if (!mounted) return;
    setState(() {
      _router = createAppRouter(_appState);
      _restoring = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_restoring || _router == null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: const Color(0xFFF7F8FA),
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.storefront_rounded,
                  size: 48,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 16),
                const CircularProgressIndicator(),
              ],
            ),
          ),
        ),
      );
    }

    return AnimatedBuilder(
      animation: _appState,
      builder: (context, _) {
        final primary = _hexColor(
              _appState.session?.branding?.theme.primaryColor,
            ) ??
            const Color(0xFF2E7D32);

        return ShadApp.custom(
          themeMode: ThemeMode.light,
          darkTheme: ShadThemeData(
            brightness: Brightness.dark,
            colorScheme: const ShadZincColorScheme.dark(),
          ),
          theme: ShadThemeData(
            brightness: Brightness.light,
            colorScheme: const ShadZincColorScheme.light(),
          ),
          appBuilder: (context) {
            return MaterialApp.router(
              title: _appState.session?.businessName ?? 'Aroll+',
              debugShowCheckedModeBanner: false,
              theme: ThemeData(
                colorScheme: ColorScheme.fromSeed(seedColor: primary),
                useMaterial3: true,
              ),
              routerConfig: _router!,
              builder: (context, child) => ShadAppBuilder(child: child!),
            );
          },
        );
      },
    );
  }
}

Color? _hexColor(String? value) {
  if (value == null || value.isEmpty) return null;
  final normalized = value.replaceFirst('#', '');
  if (normalized.length != 6) return null;
  final parsed = int.tryParse('FF$normalized', radix: 16);
  if (parsed == null) return null;
  return Color(parsed);
}
