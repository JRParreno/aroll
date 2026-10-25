import 'package:aroll_mobile/core/location/business_places_search.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a repeated address search reuses the cached Nominatim result', () async {
    var calls = 0;
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          calls += 1;
          handler.resolve(
            Response(
              requestOptions: options,
              data: [
                {
                  'lat': '14.5995',
                  'lon': '120.9842',
                  'place_id': 1,
                  'display_name': 'Manila',
                  'address': {
                    'city': 'Manila',
                    'state': 'Metro Manila',
                  },
                },
              ],
            ),
          );
        },
      ),
    );

    final search = BusinessPlacesSearch(dio: dio);
    final first = await search.autocomplete('Manila');
    final second = await search.autocomplete('manila');

    expect(first, hasLength(1));
    expect(second.single.description, first.single.description);
    expect(second.single.latitude, 14.5995);
    expect(calls, 1);
  });

  test('a short query does not call Nominatim', () async {
    var calls = 0;
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          calls += 1;
          handler.resolve(
            Response(requestOptions: options, data: const []),
          );
        },
      ),
    );

    final search = BusinessPlacesSearch(dio: dio);
    expect(await search.autocomplete('a'), isEmpty);
    expect(calls, 0);
  });
}
