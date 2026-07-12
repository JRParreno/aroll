import 'package:flutter/material.dart';

class AppNavObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    debugPrint(
      '[nav] didPush ${route.settings.name} '
      '(prev=${previousRoute?.settings.name})',
    );
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    debugPrint(
      '[nav] didPop ${route.settings.name} '
      '(prev=${previousRoute?.settings.name})',
    );
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    debugPrint(
      '[nav] didReplace ${oldRoute?.settings.name} -> ${newRoute?.settings.name}',
    );
  }
}
