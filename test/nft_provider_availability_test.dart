import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:web_dex/model/nft.dart';
import 'package:web_dex/services/nft_provider_availability.dart';

void main() {
  test(
    'owned request uses HTTPS without redirects or credentials and closes its client',
    () async {
      final client = _OwnedClient((request) async {
        expect(request.url.scheme, 'https');
        expect(request.url.host, 'moralis.gleec.com');
        expect(request.followRedirects, isFalse);
        expect(
          request.headers.keys.map((e) => e.toLowerCase()),
          isNot(anyElement(isIn(['authorization', 'x-auth-payload']))),
        );
        return http.StreamedResponse(
          Stream.value('{"result":[]}'.codeUnits),
          200,
        );
      });
      await NftProviderAvailability(
        clientFactory: () => client,
      ).ensureAvailable(NftBlockchains.eth);
      expect(client.closed, isTrue);
    },
  );

  test('deadline closes only the owned HTTP client', () async {
    final response = Completer<http.StreamedResponse>();
    final client = _OwnedClient((_) => response.future);
    final subject = NftProviderAvailability(
      clientFactory: () => client,
      deadline: const Duration(milliseconds: 5),
    );
    await expectLater(
      subject.ensureAvailable(NftBlockchains.eth),
      throwsA(isA<NftProviderUnavailable>()),
    );
    expect(client.closed, isTrue);
    response.complete(http.StreamedResponse(const Stream.empty(), 200));
  });

  test(
    'expired or future-dated availability cannot hide a new provider failure',
    () async {
      var now = DateTime.utc(2026, 11, 11);
      var calls = 0;
      final subject = NftProviderAvailability(
        clock: () => now,
        clientFactory: () => MockClient((_) async {
          calls++;
          return http.Response(
            calls == 1
                ? '{"result":[]}'
                : '{"message":"NFT feature termporary disabled."}',
            200,
          );
        }),
      );
      await subject.ensureAvailable(NftBlockchains.eth);
      now = now.subtract(const Duration(minutes: 1));
      await expectLater(
        subject.ensureAvailable(NftBlockchains.eth),
        throwsA(isA<NftProviderUnavailable>()),
      );
      now = now.add(const Duration(minutes: 2));
      await expectLater(
        subject.ensureAvailable(NftBlockchains.eth),
        throwsA(isA<NftProviderUnavailable>()),
      );
      expect(calls, 3);
    },
  );
  for (final chain in [
    NftBlockchains.eth,
    NftBlockchains.bsc,
    NftBlockchains.avalanche,
  ]) {
    test('HTTP 200 disabled is unavailable, never empty: $chain', () async {
      final subject = NftProviderAvailability(
        clientFactory: () => MockClient((request) async {
          expect(request.url.host, 'moralis.gleec.com');
          expect(request.url.scheme, 'https');
          expect(
            request.url.path,
            '/api/v2/0x${List.filled(40, '0').join()}/nft',
          );
          expect(request.headers.keys, isNot(contains('authorization')));
          return http.Response(
            '{"message":"NFT feature termporary disabled."}',
            200,
          );
        }),
      );
      await expectLater(
        subject.ensureAvailable(chain),
        throwsA(
          isA<NftProviderUnavailable>().having(
            (e) => e.reason,
            'reason',
            NftProviderFailure.disabled,
          ),
        ),
      );
    });
  }
  test(
    'valid empty list is available; simultaneous requests share one check',
    () async {
      var calls = 0;
      final response = Completer<http.Response>();
      final subject = NftProviderAvailability(
        clientFactory: () => MockClient((_) {
          calls++;
          return response.future;
        }),
      );
      final first = subject.ensureAvailable(NftBlockchains.eth);
      final second = subject.ensureAvailable(NftBlockchains.eth);
      response.complete(http.Response('{"result":[]}', 200));
      await Future.wait([first, second]);
      await subject.ensureAvailable(NftBlockchains.eth);
      expect(calls, 1);
    },
  );
  for (final value in [
    ('{"private-payload":true}', 200),
    ('not json', 200),
    ('', 500),
    ('', 302),
  ]) {
    test(
      'invalid or failed response is never a successful empty cache: $value',
      () async {
        final subject = NftProviderAvailability(
          clientFactory: () =>
              MockClient((_) async => http.Response(value.$1, value.$2)),
        );
        await expectLater(
          subject.ensureAvailable(NftBlockchains.eth),
          throwsA(
            isA<NftProviderUnavailable>().having(
              (e) => e.toString(),
              'sanitized',
              isNot(contains('private-payload')),
            ),
          ),
        );
      },
    );
  }
  test(
    'deadline terminates an unavailable request without pretending it is empty',
    () async {
      final response = Completer<http.Response>();
      final subject = NftProviderAvailability(
        deadline: const Duration(milliseconds: 5),
        clientFactory: () => MockClient((_) => response.future),
      );
      await expectLater(
        subject.ensureAvailable(NftBlockchains.eth),
        throwsA(
          isA<NftProviderUnavailable>().having(
            (e) => e.reason,
            'reason',
            NftProviderFailure.timeout,
          ),
        ),
      );
      response.complete(http.Response('{"result":[]}', 200));
    },
  );
}

class _OwnedClient extends http.BaseClient {
  _OwnedClient(this.handler);
  final Future<http.StreamedResponse> Function(http.BaseRequest) handler;
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      handler(request);
  @override
  void close() {
    closed = true;
  }
}
