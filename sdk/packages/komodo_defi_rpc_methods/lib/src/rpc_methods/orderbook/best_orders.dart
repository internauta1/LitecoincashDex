import 'package:komodo_defi_rpc_methods/src/internal_exports.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

/// Request to get best orders for a coin and action
class BestOrdersRequest
    extends BaseRequest<BestOrdersResponse, GeneralErrorResponse> {
  BestOrdersRequest({
    required String rpcPass,
    required this.coin,
    required this.action,
    required this.requestBy,
    this.excludeMine,
  }) : super(method: 'best_orders', rpcPass: rpcPass, mmrpc: RpcVersion.v2_0);

  /// Coin ticker to trade
  final String coin;

  /// Desired trade direction
  final OrderType action;

  /// Request-by selector (volume or number)
  final RequestBy requestBy;

  /// Whether to exclude orders created by the current wallet. Defaults to false in API.
  final bool? excludeMine;

  @override
  Map<String, dynamic> toJson() => super.toJson().deepMerge({
    'params': {
      'coin': coin,
      'action': action.toJson(),
      if (excludeMine != null) 'exclude_mine': excludeMine,
      'request_by': requestBy.toJson(),
    },
  });

  @override
  BestOrdersResponse parse(Map<String, dynamic> json) =>
      BestOrdersResponse.parse(json);
}

/// Response containing best orders list
class BestOrdersResponse extends BaseResponse {
  BestOrdersResponse({
    required super.mmrpc,
    required this.orders,
    this.ordersByCoin = const {},
    this.originalTickers = const {},
  });

  factory BestOrdersResponse.parse(JsonMap json) {
    final result = json.value<JsonMap>('result');

    final grouped = result.value<JsonMap>('orders');
    final byCoin = <String, List<OrderInfo>>{};
    for (final entry in grouped.entries) {
      if (entry.value is! List)
        throw const FormatException('Invalid best orders group');
      byCoin[entry.key] = List.unmodifiable(
        (entry.value as List).map(
          (row) => OrderInfo.fromJson(Map<String, dynamic>.from(row as Map)),
        ),
      );
    }
    final aliases = <String, List<String>>{};
    final rawAliases = result['original_tickers'];
    if (rawAliases != null) {
      if (rawAliases is! Map)
        throw const FormatException('Invalid original tickers');
      for (final entry in rawAliases.entries) {
        aliases[entry.key as String] = List<String>.unmodifiable(
          entry.value as List,
        );
      }
    }
    return BestOrdersResponse(
      mmrpc: json.value<String>('mmrpc'),
      orders: List.unmodifiable(byCoin.values.expand((rows) => rows)),
      ordersByCoin: Map.unmodifiable(byCoin),
      originalTickers: Map.unmodifiable(aliases),
    );
  }

  /// Sorted list of best orders that can fulfill the request
  final List<OrderInfo> orders;

  /// Preserve ticker groups and address-format aliases supplied by KDF.
  final Map<String, List<OrderInfo>> ordersByCoin;
  final Map<String, List<String>> originalTickers;

  @override
  Map<String, dynamic> toJson() => {
    'mmrpc': mmrpc,
    'result': {
      'orders': ordersByCoin.map(
        (coin, rows) => MapEntry(coin, rows.map((e) => e.toJson()).toList()),
      ),
      if (originalTickers.isNotEmpty) 'original_tickers': originalTickers,
    },
  };
}
