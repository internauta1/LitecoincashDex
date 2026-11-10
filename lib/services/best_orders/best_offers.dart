import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart' as rpc;
import 'package:rational/rational.dart';

enum BestOfferSide { buy, sell }

class BestOffersQuery {
  BestOffersQuery({
    required this.coin,
    required this.side,
    required this.generation,
    this.volume,
    this.count = 5,
  }) {
    if (coin.isEmpty ||
        (volume != null && volume! <= Rational.zero) ||
        count < 1 ||
        count > 20) {
      throw ArgumentError('Invalid best offers query');
    }
    if (volume != null &&
        (volume!.numerator * BigInt.from(10).pow(18)) % volume!.denominator !=
            BigInt.zero) {
      throw ArgumentError('Volume exceeds supported decimal precision');
    }
  }
  final String coin;
  final BestOfferSide side;
  final int generation;
  final Rational? volume;
  final int count;
  String get key =>
      '$generation:$coin:${side.name}:${volume ?? "number:$count"}';
}

/// Exact integer arithmetic; display truncates toward zero, never via double.
String formatBestOfferNumber(Rational value, [int digits = 8]) {
  if (digits < 0 || digits > 18) throw ArgumentError('Invalid precision');
  final scale = BigInt.from(10).pow(digits);
  final scaled = value.numerator.abs() * scale ~/ value.denominator;
  final prefix = value < Rational.zero ? '-' : '';
  final whole = scaled ~/ scale;
  if (digits == 0) return '$prefix$whole';
  final fraction = (scaled % scale).toString().padLeft(digits, '0');
  return '$prefix$whole.$fraction';
}

String displayBestOfferNumber(Rational value, [int digits = 8]) {
  final text = formatBestOfferNumber(value, digits);
  if (value != Rational.zero && Rational.parse(text) == Rational.zero) {
    return '${value < Rational.zero ? "-" : ""}<${formatBestOfferNumber(Rational(BigInt.one, BigInt.from(10).pow(digits)), digits)}';
  }
  return text;
}

Rational exactOrderNumber(rpc.NumericValue? value) {
  if (value == null) throw const FormatException('Missing order number');
  if (value.fraction != null) {
    return Rational(
      BigInt.parse(value.fraction!.numer),
      BigInt.parse(value.fraction!.denom),
    );
  }
  return value.rational ?? Rational.parse(value.decimal);
}

class BestOffer {
  BestOffer({required this.coin, required this.info})
    : price = exactOrderNumber(info.price),
      min = exactOrderNumber(info.baseMinVolume),
      max = exactOrderNumber(info.baseMaxVolume) {
    if (coin.isEmpty ||
        (info.uuid?.isEmpty ?? true) ||
        price <= Rational.zero ||
        min < Rational.zero ||
        max <= Rational.zero ||
        min > max) {
      throw const FormatException('Invalid best offer');
    }
  }
  final String coin;
  final rpc.OrderInfo info;
  final Rational price;
  final Rational min;
  final Rational max;
  String get uuid => info.uuid!;
  bool fits(Rational volume) => volume >= min && volume <= max;
  Rational otherAmount(Rational volume) => price * volume;
  // The existing taker form always sells its base coin. A buy query must be
  // inverted, including both volume bounds, before it can enter that form.
  Rational sellPrice(BestOfferSide side) =>
      side == BestOfferSide.sell ? price : Rational.one / price;
  Rational sellVolume(BestOffersQuery query) => query.side == BestOfferSide.sell
      ? query.volume!
      : otherAmount(query.volume!);
}

class BestOfferGroup {
  BestOfferGroup(this.coin, List<BestOffer> variants)
    : variants = List.unmodifiable(variants);
  final String coin;
  final List<BestOffer> variants;
}

class BestOffersSnapshot {
  BestOffersSnapshot({
    required this.query,
    required List<BestOffer> offers,
    required this.receivedAt,
    this.originalTickers = const {},
  }) : offers = List.unmodifiable(offers);
  factory BestOffersSnapshot.fromRpc(
    BestOffersQuery query,
    rpc.BestOrdersResponse response,
  ) {
    final offers = <BestOffer>[];
    final seen = <String>{};
    for (final entry in response.ordersByCoin.entries) {
      for (final info in entry.value) {
        if (info.isMine == true) continue;
        final offer = BestOffer(coin: entry.key, info: info);
        if (seen.add('${entry.key}:${offer.uuid}')) offers.add(offer);
      }
    }
    return BestOffersSnapshot(
      query: query,
      offers: offers,
      receivedAt: DateTime.now(),
      originalTickers: response.originalTickers,
    );
  }
  final BestOffersQuery query;
  final List<BestOffer> offers;
  final DateTime receivedAt;
  final Map<String, List<String>> originalTickers;
  String canonicalCoin(String coin) {
    for (final entry in originalTickers.entries) {
      if (entry.value.contains(coin)) return entry.key;
    }
    return coin;
  }

  List<BestOfferGroup> groups() {
    final grouped = <String, List<BestOffer>>{};
    for (final offer in offers) {
      grouped
          .putIfAbsent('${canonicalCoin(offer.coin)}:${offer.uuid}', () => [])
          .add(offer);
    }
    return grouped.values
        .map((rows) => BestOfferGroup(canonicalCoin(rows.first.coin), rows))
        .toList();
  }
}

/// Direction-adjusted comparison for a fixed amount of the reference coin.
/// Negative means a cheaper buy; positive means a better sell.
Rational? bestOfferDifference(
  BestOffer offer,
  Rational? referenceUsd,
  Rational? otherUsd,
) {
  if (referenceUsd == null ||
      otherUsd == null ||
      referenceUsd <= Rational.zero ||
      otherUsd <= Rational.zero) {
    return null;
  }
  return ((offer.price * otherUsd / referenceUsd) - Rational.one) *
      Rational.fromInt(100);
}

abstract interface class BestOffersRepository {
  Future<BestOffersSnapshot> fetch(BestOffersQuery query);
}
