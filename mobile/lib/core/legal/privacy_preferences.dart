import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Device-local flags only. Workplace consent is stored on the employee
/// profile (`legal_consent_accepted`) and is not this permissions intro flag.
class PrivacyPreferences {
  PrivacyPreferences(this._storage);

  final FlutterSecureStorage _storage;

  static const _introKey = 'aroll_permissions_intro_seen';

  Future<bool> hasSeenPermissionsIntro() async {
    return (await _storage.read(key: _introKey)) == '1';
  }

  Future<void> markPermissionsIntroSeen() async {
    await _storage.write(key: _introKey, value: '1');
  }
}
