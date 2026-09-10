import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Device-local flag for the one-time permissions rationale screen.
/// Legal/biometric consent is stored on the server, not here.
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
