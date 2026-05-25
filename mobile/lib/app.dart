import 'package:aroll_mobile/core/app_state.dart';
import 'package:aroll_mobile/core/di/injection.dart';
import 'package:aroll_mobile/core/router/app_router.dart';
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
  late final GoRouter _router = createAppRouter(_appState);

  @override
  Widget build(BuildContext context) {
    return ShadApp.custom(
      themeMode: ThemeMode.light,
      darkTheme: ShadThemeData(brightness: Brightness.dark, colorScheme: const ShadZincColorScheme.dark()),
      theme: ShadThemeData(brightness: Brightness.light, colorScheme: const ShadZincColorScheme.light()),
      appBuilder: (context) {
        return MaterialApp.router(
          title: 'Aroll+',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E7D32)),
            useMaterial3: true,
          ),
          routerConfig: _router,
          builder: (context, child) => ShadAppBuilder(child: child!),
        );
      },
    );
  }
}
