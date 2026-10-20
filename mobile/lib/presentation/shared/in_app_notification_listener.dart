import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Owner-side poll interval. Employee banners use a shorter interval.
const Duration ownerInAppPollInterval = Duration(seconds: 60);

/// Foreground banner for newly arrived inbox items while the app is open.
class InAppNotificationListener extends StatefulWidget {
  const InAppNotificationListener({
    super.key,
    required this.child,
    required this.fetchLatest,
    required this.onOpen,
  });

  final Widget child;
  final Future<List<Map<String, dynamic>>> Function() fetchLatest;
  final Future<void> Function(Map<String, dynamic> item) onOpen;

  @override
  State<InAppNotificationListener> createState() =>
      _InAppNotificationListenerState();
}

class _InAppNotificationListenerState extends State<InAppNotificationListener>
    with WidgetsBindingObserver {
  Timer? _timer;
  String? _seenId;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _poll(initial: true);
    _timer = Timer.periodic(ownerInAppPollInterval, (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _poll();
  }

  Future<void> _poll({bool initial = false}) async {
    try {
      final items = await widget.fetchLatest();
      if (!mounted || items.isEmpty) {
        if (initial) _ready = true;
        return;
      }
      final newest = items.first;
      final id = '${newest['id'] ?? ''}';
      final unread = newest['is_read'] != true;
      if (!_ready) {
        _seenId = id;
        _ready = true;
        return;
      }
      if (id.isEmpty || id == _seenId || !unread) return;
      _seenId = id;
      final title = '${newest['title'] ?? 'Notification'}';
      final message = '${newest['message'] ?? ''}';
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            message.isEmpty ? title : '$title\n$message',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          action: SnackBarAction(
            label: 'View',
            onPressed: () => widget.onOpen(newest),
          ),
        ),
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

Future<void> openNotificationDeepLink(
  BuildContext context,
  String destination,
) async {
  if (!context.mounted || destination.isEmpty) return;
  context.push(destination);
}
