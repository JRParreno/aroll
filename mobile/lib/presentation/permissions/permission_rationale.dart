import 'package:aroll_mobile/presentation/shared/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

enum AppDevicePermission { camera, location, notifications }

extension AppDevicePermissionX on AppDevicePermission {
  String get title {
    switch (this) {
      case AppDevicePermission.camera:
        return 'Camera';
      case AppDevicePermission.location:
        return 'Location';
      case AppDevicePermission.notifications:
        return 'Notifications';
    }
  }

  String get explanation {
    switch (this) {
      case AppDevicePermission.camera:
        return 'Required for face registration and face-based attendance.';
      case AppDevicePermission.location:
        return 'Required to verify that attendance occurs within the business geofence.';
      case AppDevicePermission.notifications:
        return 'Required for attendance and system notifications.';
    }
  }

  IconData get icon {
    switch (this) {
      case AppDevicePermission.camera:
        return Icons.photo_camera_outlined;
      case AppDevicePermission.location:
        return Icons.location_on_outlined;
      case AppDevicePermission.notifications:
        return Icons.notifications_outlined;
    }
  }
}

Future<bool> showPermissionRationale(
  BuildContext context, {
  required AppDevicePermission permission,
}) async {
  final proceed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Allow ${permission.title}?'),
      content: Text(permission.explanation),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Not now'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primaryDark,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Continue'),
        ),
      ],
    ),
  );
  return proceed == true;
}

Future<bool> requestCameraWithRationale(BuildContext context) async {
  final status = await Permission.camera.status;
  if (status.isGranted || status.isLimited) return true;
  if (!context.mounted) return false;
  if (status.isPermanentlyDenied) {
    return _openSettingsPrompt(
      context,
      title: 'Camera access is off',
      message:
          'Enable Camera in settings so you can enroll your face and record attendance.',
    );
  }
  final proceed = await showPermissionRationale(
    context,
    permission: AppDevicePermission.camera,
  );
  if (!proceed) return false;
  final result = await Permission.camera.request();
  return result.isGranted || result.isLimited;
}

Future<bool> requestNotificationWithRationale(BuildContext context) async {
  final status = await Permission.notification.status;
  if (status.isGranted || status.isLimited) return true;
  if (!context.mounted) return false;
  if (status.isPermanentlyDenied) {
    return _openSettingsPrompt(
      context,
      title: 'Notifications are off',
      message:
          'Enable Notifications in settings if you want device alerts for attendance and other updates.',
    );
  }
  final proceed = await showPermissionRationale(
    context,
    permission: AppDevicePermission.notifications,
  );
  if (!proceed) return false;
  final result = await Permission.notification.request();
  return result.isGranted || result.isLimited;
}

Future<bool> requestLocationWithRationale(BuildContext context) async {
  final serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    if (!context.mounted) return false;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Turn on Location'),
        content: const Text(
          'Location services are off. Aroll+ uses GPS only to confirm live attendance is inside the workplace geofence.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    return false;
  }

  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.always ||
      permission == LocationPermission.whileInUse) {
    return true;
  }
  if (!context.mounted) return false;
  if (permission == LocationPermission.deniedForever) {
    return _openSettingsPrompt(
      context,
      title: 'Location access is off',
      message:
          'Enable Location in settings so Aroll+ can confirm you are at the workplace during Time In and Time Out.',
    );
  }

  final proceed = await showPermissionRationale(
    context,
    permission: AppDevicePermission.location,
  );
  if (!proceed) return false;
  permission = await Geolocator.requestPermission();
  return permission == LocationPermission.always ||
      permission == LocationPermission.whileInUse;
}

Future<bool> _openSettingsPrompt(
  BuildContext context, {
  required String title,
  required String message,
}) async {
  final open = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primaryDark,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Open settings'),
        ),
      ],
    ),
  );
  if (open == true) {
    await openAppSettings();
  }
  return false;
}
