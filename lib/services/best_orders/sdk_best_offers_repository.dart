import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'dart:async';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart' as rpc;
import 'package:komodo_defi_types/komodo_defi_types.dart'
    show KomodoDefiRpcMethodsExtension;
import 'best_offers.dart';

class SharedBestOffersRepository implements BestOffersRepository {
  SharedBestOffersRepository({
    required this.request,
    required this.currentGeneration,
    this.timeout = const Duration(seconds: 12),
  });
  final Future<rpc.BestOrdersResponse> Function(BestOffersQuery) request;
  final int Function() currentGeneration;
  final Duration timeout;
  final _inFlight = <String, Future<BestOffersSnapshot>>{};
  @override
  Future<BestOffersSnapshot> fetch(BestOffersQuery query) {
    if (currentGeneration() != query.generation) {
      throw StateError('Session changed');
    }
    var task = _inFlight[query.key];
    if (task == null) {
      task = _load(query);
      _inFlight[query.key] = task;
      void release() {
        if (identical(_inFlight[query.key], task)) _inFlight.remove(query.key);
      }

      unawaited(
        task.then<void>(
          (_) => release(),
          onError: (Object _, StackTrace __) => release(),
        ),
      );
    }
    // A UI timeout must not remove an underlying request that is still running.
    return task.timeout(timeout);
  }

  Future<BestOffersSnapshot> _load(BestOffersQuery query) async {
    final result = await request(query);
    if (currentGeneration() != query.generation) {
      throw StateError('Session changed');
    }
    return BestOffersSnapshot.fromRpc(query, result);
  }
}

class SdkBestOffersRepository extends SharedBestOffersRepository {
  SdkBestOffersRepository(KomodoDefiSdk sdk)
    : super(
        currentGeneration: () => sdk.auth.authGeneration,
        request: (query) => sdk.client.rpc.orderbook.bestOrders(
          coin: query.coin,
          action: query.side == BestOfferSide.buy
              ? rpc.OrderType.buy
              : rpc.OrderType.sell,
          requestBy: query.volume == null
              ? rpc.RequestBy.number(query.count)
              : rpc.RequestBy.volume(formatBestOfferNumber(query.volume!, 18)),
          excludeMine: true,
        ),
      );
}
