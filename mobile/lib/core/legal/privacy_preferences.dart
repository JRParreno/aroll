import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Account-scoped read/write for permissions onboarding markers.
abstract class PermissionsOnboardingStore {
  Future<bool> hasAccountOnboardingCompleted(String userId);
  Future<void> markAccountOnboardingCompleted(String userId);
  Future<bool> hasDeviceReviewedForAccount(String userId);
  Future<void> markDeviceReviewedForAccount(String userId);
  Future<void> clearLegacyDeviceFlag();
}

/// Account-scoped preferences for permissions onboarding.
///
/// Legal consent is server-side. OS permission grants are device/OS-level.
/// This class only stores:
/// - a local cache of account onboarding completion (keyed by user id)
/// - a per-account device-reviewed marker (so a new device can still prompt
///   for OS permissions without inheriting another account's state)
class PrivacyPreferences implements PermissionsOnboardingStore {
  PrivacyPreferences(this._storage);

  final FlutterSecureStorage _storage;

  /// Legacy device-global key — no longer authoritative; left unread.
  static const _legacyIntroKey = 'aroll_permissions_intro_seen';

  String _accountCompletedKey(String userId) =>
      'aroll_permissions_onboarding_completed_$userId';

  String _deviceReviewedKey(String userId) =>
      'aroll_permissions_device_reviewed_$userId';

  @override
  Future<bool> hasAccountOnboardingCompleted(String userId) async {
    final id = userId.trim();
    if (id.isEmpty) return false;
    return (await _storage.read(key: _accountCompletedKey(id))) == '1';
  }

  @override
  Future<void> markAccountOnboardingCompleted(String userId) async {
    final id = userId.trim();
    if (id.isEmpty) return;
    await _storage.write(key: _accountCompletedKey(id), value: '1');
  }

  @override
  Future<bool> hasDeviceReviewedForAccount(String userId) async {
    final id = userId.trim();
    if (id.isEmpty) return false;
    return (await _storage.read(key: _deviceReviewedKey(id))) == '1';
  }

  @override
  Future<void> markDeviceReviewedForAccount(String userId) async {
    final id = userId.trim();
    if (id.isEmpty) return;
    await _storage.write(key: _deviceReviewedKey(id), value: '1');
  }

  @override
  Future<void> clearLegacyDeviceFlag() async {
    await _storage.delete(key: _legacyIntroKey);
  }
}
