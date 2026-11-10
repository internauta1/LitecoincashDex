import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_sdk/src/assets/asset_manager.dart';
import 'package:komodo_defi_sdk/src/transaction_history/transaction_history_manager.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:komodo_persistence_layer/komodo_persistence_layer.dart';
import 'package:mocktail/mocktail.dart';
import 'package:web_dex/bloc/cex_market_data/models/graph_cache.dart';
import 'package:web_dex/bloc/cex_market_data/portfolio_growth/portfolio_growth_repository.dart';
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';
import 'package:web_dex/bloc/transaction_history/transaction_history_repo.dart';
import '../test_units/tests/utils/test_util.dart';

class _Sdk extends Mock implements KomodoDefiSdk {}

class _Assets extends Mock implements AssetManager {}

class _Asset extends Mock implements Asset {}

class _Transactions extends Mock implements TransactionHistoryManager {}

class _Auth extends Mock implements KomodoDefiLocalAuth {}

class _Coins extends Mock implements CoinsRepo {}

class _Cache extends Mock implements PersistenceProvider<String, GraphCache> {}

void main() {
  final coin = setCoin(coinAbbr: 'KMD');
  final asset = _Asset();
  const user = KdfUser(
    walletId: WalletId(
      name: 'offline-fixture',
      authOptions: AuthOptions(derivationMethod: DerivationMethod.iguana),
    ),
    isBip39Seed: false,
  );
  late _Transactions transactions;
  late SdkTransactionHistoryRepository history;
  late PortfolioGrowthRepository chart;
  setUp(() {
    final sdk = _Sdk();
    final assets = _Assets();
    final auth = _Auth();
    final coins = _Coins();
    final cache = _Cache();
    transactions = _Transactions();
    when(() => sdk.assets).thenReturn(assets);
    when(() => assets.available).thenReturn({coin.id: asset});
    when(() => sdk.transactions).thenReturn(transactions);
    when(() => sdk.auth).thenReturn(auth);
    when(() => auth.currentUser).thenAnswer((_) async => user);
    when(() => coins.getCoinFromId(coin.id)).thenReturn(coin);
    history = SdkTransactionHistoryRepository(sdk: sdk);
    chart = PortfolioGrowthRepository(
      transactionHistoryRepo: history,
      cacheProvider: cache,
      coinsRepository: coins,
      sdk: sdk,
    );
  });
  test(
    'history provider failure reaches completed history and chart as an error',
    () async {
      when(
        () => transactions.getTransactionHistory(
          asset,
          pagination: const PagePagination(pageNumber: 1, itemsPerPage: 2000),
        ),
      ).thenThrow(
        const HistoryProviderException(
          HistoryProviderFailure.unavailable,
          statusCode: 500,
        ),
      );
      await expectLater(
        history.fetchCompletedTransactions(coin.id),
        throwsA(isA<TransactionFetchException>()),
      );
      await expectLater(
        chart.getPortfolioGrowthChart(
          [coin],
          fiatCoinId: 'USDT',
          walletId: 'offline-fixture',
          useCache: false,
        ),
        throwsA(isA<TransactionFetchException>()),
      );
    },
  );
  test(
    'valid zero-transactions response is a successful empty history',
    () async {
      when(
        () => transactions.getTransactionHistory(
          asset,
          pagination: const PagePagination(pageNumber: 1, itemsPerPage: 2000),
        ),
      ).thenAnswer(
        (_) async => const TransactionPage(
          transactions: [],
          total: 0,
          currentPage: 1,
          totalPages: 0,
        ),
      );
      expect(await history.fetchCompletedTransactions(coin.id), isEmpty);
    },
  );
}
