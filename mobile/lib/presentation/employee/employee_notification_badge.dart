typedef BadgeWatermarkRead = Future<String?> Function(String key);
typedef BadgeWatermarkWrite = Future<void> Function(String key, String value);

bool notificationIsUnread(Map<String, dynamic> item) => item['is_read'] != true;

/// Raw `created_at` of the newest notification in [items].
String? newestNotificationCreatedAt(Iterable<Map<String, dynamic>> items) {
  String? raw;
  DateTime? latest;
  for (final item in items) {
    final value = '${item['created_at'] ?? ''}'.trim();
    if (value.isEmpty) continue;
    final parsed = DateTime.tryParse(value);
    if (parsed == null) continue;
    if (latest == null || parsed.isAfter(latest)) {
      latest = parsed;
      raw = value;
    }
  }
  return raw;
}

/// Move the inbox watermark forward. An older value cannot replace it.
String? advanceNotificationSeenThrough(String? current, String? candidate) {
  final nextRaw = candidate?.trim();
  if (nextRaw == null || nextRaw.isEmpty) return _blankToNull(current);
  if (DateTime.tryParse(nextRaw) == null) return _blankToNull(current);
  final prevRaw = _blankToNull(current);
  if (prevRaw == null) return nextRaw;
  final prev = DateTime.tryParse(prevRaw);
  final next = DateTime.parse(nextRaw);
  if (prev == null || next.isAfter(prev)) return nextRaw;
  return prevRaw;
}

/// Badge count after the inbox has been opened.
///
/// [unreadCount] is the full unread total. Once [seenThroughCreatedAt] is set,
/// that total is ignored and [unreadCountAfterSeenThrough] is the badge.
int resolveEmployeeNotificationBadge({
  required String? seenThroughCreatedAt,
  required int? unreadCount,
  required int? unreadCountAfterSeenThrough,
}) {
  final opened =
      seenThroughCreatedAt != null && seenThroughCreatedAt.trim().isNotEmpty;
  final value = opened ? unreadCountAfterSeenThrough : unreadCount;
  if (value == null || value < 0) return 0;
  return value;
}

List<Map<String, dynamic>> markNotificationsReadThrough(
  List<Map<String, dynamic>> items,
  String? createdThrough,
) {
  final cutoff = DateTime.tryParse((createdThrough ?? '').trim());
  return [
    for (final item in items) _markItemRead(item, cutoff),
  ];
}

bool intendedNotificationsMarked({
  required List<Map<String, dynamic>> before,
  required List<Map<String, dynamic>> after,
}) {
  final stillUnread = after
      .where(notificationIsUnread)
      .map((item) => '${item['id'] ?? ''}')
      .where((id) => id.isNotEmpty)
      .toSet();
  for (final item in before) {
    if (!notificationIsUnread(item)) continue;
    final id = '${item['id'] ?? ''}';
    if (id.isNotEmpty && stillUnread.contains(id)) return false;
  }
  return true;
}

bool notificationRecordsRetained({
  required List<Map<String, dynamic>> before,
  required List<Map<String, dynamic>> after,
}) {
  final afterIds = after.map((item) => '${item['id'] ?? ''}').toSet();
  for (final item in before) {
    final id = '${item['id'] ?? ''}';
    if (id.isNotEmpty && !afterIds.contains(id)) return false;
  }
  return true;
}

Map<String, dynamic> _markItemRead(
  Map<String, dynamic> item,
  DateTime? cutoff,
) {
  final copy = Map<String, dynamic>.from(item);
  if (!notificationIsUnread(copy)) return copy;
  final created = DateTime.tryParse('${copy['created_at'] ?? ''}'.trim());
  if (cutoff != null && created != null && created.isAfter(cutoff)) {
    return copy;
  }
  copy['is_read'] = true;
  return copy;
}

String? _blankToNull(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed;
}

/// Per-employee inbox watermark. Memory is the session source; storage keeps
/// it across a UI refresh that reloads the home screen.
class EmployeeNotificationBadgeStore {
  EmployeeNotificationBadgeStore({
    BadgeWatermarkRead? read,
    BadgeWatermarkWrite? write,
  })  : _read = read,
        _write = write;

  final BadgeWatermarkRead? _read;
  final BadgeWatermarkWrite? _write;
  final Map<String, String> _memory = {};
  List<Map<String, dynamic>>? _prepared;
  DateTime? _preparedAt;

  String _key(String userId) => 'employee_notification_inbox_seen_$userId';

  Future<String?> seenThrough(String userId) async {
    final cached = _blankToNull(_memory[userId]);
    if (cached != null) return cached;
    final read = _read;
    if (read == null) return null;
    try {
      final stored = _blankToNull(await read(_key(userId)));
      if (stored != null) _memory[userId] = stored;
      return stored;
    } catch (_) {
      return null;
    }
  }

  Future<String?> acknowledge(
    String userId,
    List<Map<String, dynamic>> items,
  ) async {
    final current = await seenThrough(userId);
    final next = advanceNotificationSeenThrough(
      current,
      newestNotificationCreatedAt(items),
    );
    if (next == null) return current;
    _memory[userId] = next;
    final write = _write;
    if (write != null) {
      try {
        await write(_key(userId), next);
      } catch (_) {}
    }
    return next;
  }

  void rememberPrepared(List<Map<String, dynamic>> items) {
    _prepared = [
      for (final item in items) Map<String, dynamic>.from(item),
    ];
    _preparedAt = DateTime.now();
  }

  /// Inbox list already loaded for this open, if it is still fresh.
  List<Map<String, dynamic>>? takePrepared() {
    final items = _prepared;
    final at = _preparedAt;
    _prepared = null;
    _preparedAt = null;
    if (items == null || at == null) return null;
    if (DateTime.now().difference(at) > const Duration(seconds: 5)) {
      return null;
    }
    return items;
  }
}
