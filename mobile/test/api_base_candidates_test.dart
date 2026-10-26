import 'package:aroll_mobile/core/network/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const platformDefault = 'http://10.0.2.2:8000/api/v1';

  test('unlocked builds keep the configured URL and local fallbacks', () {
    expect(
      resolveApiBaseCandidates(
        configuredUrl: 'https://arollplus.duckdns.org/api/v1',
        lockedUrl: '',
        locked: false,
        platformDefault: platformDefault,
      ),
      [
        'https://arollplus.duckdns.org/api/v1',
        platformDefault,
        'http://127.0.0.1:8000/api/v1',
      ],
    );
  });

  test('a locked test build uses only its explicit local URL', () {
    expect(
      resolveApiBaseCandidates(
        configuredUrl: 'https://arollplus.duckdns.org/api/v1',
        lockedUrl: 'http://192.168.100.83:8000/api/v1',
        locked: true,
        platformDefault: platformDefault,
      ),
      ['http://192.168.100.83:8000/api/v1'],
    );
  });

  test('a locked test build refuses the production host', () {
    expect(
      () => resolveApiBaseCandidates(
        configuredUrl: null,
        lockedUrl: 'https://arollplus.duckdns.org/api/v1',
        locked: true,
        platformDefault: platformDefault,
      ),
      throwsStateError,
    );
  });
}
