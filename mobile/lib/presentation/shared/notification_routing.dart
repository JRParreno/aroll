/// Destination used when a notification is opened.
String notificationDestination({
  required String type,
  String deepLink = '',
  String entityId = '',
  bool owner = false,
}) {
  if (deepLink.trim().isNotEmpty) return deepLink.trim();
  if (owner) {
    if (type.startsWith('leave')) {
      return entityId.isNotEmpty ? '/owner/leave/$entityId' : '/owner/leave';
    }
    if (type.startsWith('overtime') ||
        type.contains('incomplete') ||
        type.startsWith('attendance')) {
      return '/owner/attendance';
    }
    if (type.startsWith('payroll')) return '/owner/payroll';
    if (type.startsWith('schedule')) return '/owner/schedule';
    return '/owner/home';
  }
  if (type.startsWith('leave')) {
    return entityId.isNotEmpty ? '/leave-requests/$entityId' : '/leave-requests';
  }
  if (type.startsWith('overtime') ||
      type.contains('incomplete') ||
      type.startsWith('attendance')) {
    return '/shift-history';
  }
  if (type.startsWith('payroll')) return '/payslip';
  if (type.startsWith('schedule')) return '/schedule';
  return '/home';
}

IconDataForType notificationIconKind(String type) {
  if (type.startsWith('leave')) return IconDataForType.leave;
  if (type.startsWith('overtime')) return IconDataForType.overtime;
  if (type.contains('incomplete') || type.startsWith('attendance')) {
    return IconDataForType.attendance;
  }
  if (type.startsWith('payroll')) return IconDataForType.payroll;
  if (type.startsWith('schedule')) return IconDataForType.schedule;
  return IconDataForType.generic;
}

enum IconDataForType { leave, overtime, attendance, payroll, schedule, generic }
