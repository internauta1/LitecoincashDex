import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:komodo_defi_sdk/src/pubkeys/pubkey_manager.dart';
import 'package:komodo_defi_sdk/src/transaction_history/strategies/etherscan_transaction_history_strategy.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:mocktail/mocktail.dart';

class _Pubkeys extends Mock implements PubkeyManager {}

class _Api extends Mock implements ApiClient {}

class _BlockedClient extends http.BaseClient {
  bool closed = false;
  final pending = Completer<http.StreamedResponse>();
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      pending.future;
  @override
  void close() {
    closed = true;
  }
}

void main() {
  final asset = Asset.fromJson({
    'coin': 'ETH',
    'type': 'ETH',
    'fname': 'Ethereum',
    'chain_id': 1,
    'is_testnet': false,
    'nodes': [
      {'url': 'https://rpc.invalid'},
    ],
    'swap_contract_address': '0x0000000000000000000000000000000000000001',
    'fallback_swap_contract': '0x0000000000000000000000000000000000000001',
  });
  late _Pubkeys pubkeys;
  const page = PagePagination(pageNumber: 1, itemsPerPage: 20);
  setUp(() {
    pubkeys = _Pubkeys();
    when(() => pubkeys.getPubkeys(asset)).thenAnswer(
      (_) async => AssetPubkeys(
        assetId: asset.id,
        keys: [
          PubkeyInfo(
            address: '0x0000000000000000000000000000000000000001',
            derivationPath: null,
            chain: null,
            balance: BalanceInfo.zero(),
            coinTicker: 'ETH',
          ),
        ],
        availableAddressesCount: 1,
        syncStatus: SyncStatusEnum.success,
      ),
    );
  });
  EtherscanTransactionStrategy strategy(http.Client client) =>
      EtherscanTransactionStrategy(
        pubkeyManager: pubkeys,
        httpClient: client,
        baseUrl: 'https://history.invalid/api',
      );
  test(
    'valid empty history performs HTTP even in debug and remains empty',
    () async {
      var calls = 0;
      final subject = strategy(
        MockClient((request) async {
          calls++;
          return http.Response('{"result":{"transactions":[]}}', 200);
        }),
      );
      final result = await subject.fetchTransactionHistory(_Api(), asset, page);
      expect(calls, 1);
      expect(result.transactions, isEmpty);
    },
  );
  test('HTTP 500 is unavailable, never a successful empty history', () async {
    final subject = strategy(
      MockClient((_) async => http.Response('unavailable', 500)),
    );
    await expectLater(
      subject.fetchTransactionHistory(_Api(), asset, page),
      throwsA(
        isA<HistoryProviderException>()
            .having(
              (e) => e.reason,
              'reason',
              HistoryProviderFailure.unavailable,
            )
            .having((e) => e.statusCode, 'status', 500),
      ),
    );
  });
  test(
    'malformed HTTP 200 is invalid data and contains no response payload',
    () async {
      final subject = strategy(
        MockClient((_) async => http.Response('{"private-payload":1}', 200)),
      );
      await expectLater(
        subject.fetchTransactionHistory(_Api(), asset, page),
        throwsA(
          isA<HistoryProviderException>()
              .having(
                (e) => e.reason,
                'reason',
                HistoryProviderFailure.invalidResponse,
              )
              .having(
                (e) => e.toString(),
                'sanitized',
                isNot(contains('private-payload')),
              ),
        ),
      );
    },
  );
  test(
    'deadline closes only the owned request client and reports timeout',
    () async {
      final client = _BlockedClient();
      final subject = EtherscanTransactionStrategy(
        pubkeyManager: pubkeys,
        httpClientFactory: () => client,
        requestTimeout: const Duration(milliseconds: 5),
        baseUrl: 'https://history.invalid/api',
      );
      await expectLater(
        subject.fetchTransactionHistory(_Api(), asset, page),
        throwsA(
          isA<HistoryProviderException>().having(
            (e) => e.reason,
            'reason',
            HistoryProviderFailure.timeout,
          ),
        ),
      );
      expect(client.closed, isTrue);
    },
  );
  test('borrowed client is not closed by a request deadline', () async {
    final client = _BlockedClient();
    final subject = EtherscanTransactionStrategy(
      pubkeyManager: pubkeys,
      httpClient: client,
      requestTimeout: const Duration(milliseconds: 5),
    );
    await expectLater(
      subject.fetchTransactionHistory(_Api(), asset, page),
      throwsA(isA<HistoryProviderException>()),
    );
    expect(client.closed, isFalse);
    subject.dispose();
    expect(client.closed, isTrue);
  });
}
