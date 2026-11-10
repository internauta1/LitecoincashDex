import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:mocktail/mocktail.dart';
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';
import 'package:web_dex/bloc/fiat/fiat_onramp_form/fiat_form_bloc.dart';
import 'package:web_dex/bloc/fiat/fiat_repository.dart';
import 'package:web_dex/bloc/fiat/models/models.dart';
import 'package:web_dex/services/storage/base_storage.dart';

class _Repo extends Mock implements FiatRepository {}

class _Coins extends Mock implements CoinsRepo {}

class _Sdk extends Mock implements KomodoDefiSdk {}

class _Storage extends Fake implements BaseStorage {
  @override
  Future<dynamic> read(String key) async => null;
}

void main() {
  setUpAll(() => registerFallbackValue(CryptoCurrency.bitcoin()));
  for (final failsWithArgument in [false, true]) {
    test(
      'payment methods ${failsWithArgument ? "ArgumentError" : "empty response"} becomes visible failure without submission',
      () async {
        final repo = _Repo();
        final sdk = _Sdk();
        when(() => repo.getPaymentMethodsList(any(), any(), any())).thenAnswer(
          (_) => failsWithArgument
              ? Stream<List<FiatPaymentMethod>>.error(
                  ArgumentError('synthetic invalid response'),
                )
              : Stream.value([]),
        );
        final bloc = FiatFormBloc(
          repository: repo,
          coinsRepo: _Coins(),
          sdk: sdk,
          storage: _Storage(),
        );
        final failure = bloc.stream.firstWhere(
          (s) => s.status == FiatFormStatus.failure,
        );
        bloc.add(const FiatFormPaymentMethodsRefreshRequested());
        final state = await failure.timeout(const Duration(seconds: 3));
        expect(state.canSubmit, isFalse);
        expect(state.paymentMethods, isEmpty);
        expect(state.selectedPaymentMethod.isNone, isTrue);
        expect(
          state.providerError,
          'Payment methods are currently unavailable.',
        );
        when(
          () => repo.getPaymentMethodsList(any(), any(), any()),
        ).thenAnswer((_) => Stream.value(defaultFiatPaymentMethods));
        final recovery = bloc.stream.firstWhere(
          (s) => s.status == FiatFormStatus.success,
        );
        bloc.add(const FiatFormPaymentMethodsRefreshRequested());
        expect(
          (await recovery.timeout(const Duration(seconds: 3))).paymentMethods,
          isNotEmpty,
        );
        verifyZeroInteractions(sdk);
        await bloc.close();
      },
    );
  }
}
