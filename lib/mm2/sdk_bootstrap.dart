/// A bootstrap instance permanently owns the outcome of one SDK generation.
final class SdkBootstrap<T> {
  Future<T>? _attempt;
  Future<T> initialize(Future<T> Function() start) =>
      _attempt ??= Future.microtask(start);
}
