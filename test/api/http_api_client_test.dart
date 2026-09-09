import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qwallet_scan/api/api_client.dart';
import 'package:qwallet_scan/api/api_exception.dart';

/// Records what the client sent, and replies with whatever the test says.
MockClient respondWith(int status, String body, {List<http.Request>? capture}) {
  return MockClient((request) async {
    capture?.add(request);
    return http.Response(
      body,
      status,
      headers: {'content-type': 'application/json'},
    );
  });
}

void main() {
  group('HttpApiClient', () {
    test(
      'login posts the identifier and password, and returns the session',
      () async {
        final sent = <http.Request>[];
        final client = HttpApiClient(
          baseUrl: 'https://api.test',
          httpClient: respondWith(
            200,
            jsonEncode({
              'token': 'jwt-abc',
              'user': {
                'id': 7,
                'email': 'sam@shop.qa',
                'name': 'Sam',
                'role': 'staff',
                'businessIds': ['biz-1'],
              },
            }),
            capture: sent,
          ),
        );

        final session = await client.login(
          identifier: 'sam@shop.qa',
          password: 'pw',
        );

        expect(sent.single.url.toString(), 'https://api.test/api/auth/login');
        expect(jsonDecode(sent.single.body), {
          'identifier': 'sam@shop.qa',
          'password': 'pw',
        });
        expect(session.token, 'jwt-abc');
        expect(session.businessIds, ['biz-1']);
      },
    );

    test(
      'an authenticated call sends the bearer token from the reader',
      () async {
        final sent = <http.Request>[];
        final client = HttpApiClient(
          baseUrl: 'https://api.test',
          httpClient: respondWith(200, _cardJson, capture: sent),
          tokenReader: () => 'jwt-abc',
        );

        await client.fetchCard(cardId: 'ABC123', businessId: 'biz-1');

        expect(sent.single.headers['Authorization'], 'Bearer jwt-abc');
        expect(
          sent.single.url.toString(),
          'https://api.test/api/passes/ABC123?businessId=biz-1',
        );
      },
    );

    test(
      'a card id with a slash in it cannot escape its path segment',
      () async {
        final sent = <http.Request>[];
        final client = HttpApiClient(
          baseUrl: 'https://api.test',
          httpClient: respondWith(200, _cardJson, capture: sent),
        );

        await client.fetchCard(cardId: 'a/../b', businessId: 'biz-1');

        expect(sent.single.url.path, '/api/passes/a%2F..%2Fb');
      },
    );

    test('a non-2xx becomes an ApiException of the right kind', () async {
      final client = HttpApiClient(
        baseUrl: 'https://api.test',
        httpClient: respondWith(404, '{"error":"Card not found"}'),
      );

      expect(
        () => client.fetchCard(cardId: 'NOPE', businessId: 'biz-1'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.kind,
            'kind',
            ApiErrorKind.notFound,
          ),
        ),
      );
    });

    test(
      'a socket failure becomes a network ApiException, not a raw error',
      () async {
        final client = HttpApiClient(
          baseUrl: 'https://api.test',
          httpClient: MockClient(
            (_) async => throw const SocketExceptionStub(),
          ),
        );

        expect(
          () => client.fetchCard(cardId: 'ABC123', businessId: 'biz-1'),
          throwsA(
            isA<ApiException>().having(
              (e) => e.kind,
              'kind',
              ApiErrorKind.network,
            ),
          ),
        );
      },
    );

    test('addStamps posts the increment and returns the new state', () async {
      final sent = <http.Request>[];
      final client = HttpApiClient(
        baseUrl: 'https://api.test',
        httpClient: respondWith(
          200,
          jsonEncode({
            'cardId': 'ABC123',
            'stampCount': 5,
            'stampsRequired': 10,
            'rewardsAvailable': 0,
          }),
          capture: sent,
        ),
      );

      final result = await client.addStamps(
        cardId: 'ABC123',
        businessId: 'biz-1',
        increment: 2,
      );

      expect(jsonDecode(sent.single.body), {
        'businessId': 'biz-1',
        'increment': 2,
      });
      expect(result.stampCount, 5);
      expect(result.rewardsAvailable, 0);
    });
  });
}

/// http's MockClient rethrows whatever the handler throws; this stands in for a
/// dropped connection without needing dart:io in a test that also runs on web.
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}

const _cardJson = '''
{"cardId":"ABC123","businessId":"biz-1","userName":"Ali","userEmail":"a@b.qa",
 "userPhone":null,"templateType":"reward","stampCount":3,"rewardsAvailable":0,
 "pointsBalance":0,"pointsExpiry":null,"membershipNumber":null,
 "membershipCategory":null,"membershipExpiry":null,
 "merchantData":{"businessName":"Wake","rewardDescription":"A free flat white",
 "stampsRequired":10}}
''';
