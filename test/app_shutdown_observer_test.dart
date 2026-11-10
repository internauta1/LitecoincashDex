import 'dart:async';
import 'package:bloc/bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/bloc/app_bloc_observer.dart';
import 'package:web_dex/bloc/app_shutdown.dart';

class _Subscriber extends Cubit<int> {
  _Subscriber(Stream<int> source, this.order) : super(0) {
    subscription = source.listen((value) {
      order.add('event');
      emit(value);
    });
  }
  final List<String> order;
  late final StreamSubscription<int> subscription;
  @override
  Future<void> close() async {
    order.add('cancel');
    await subscription.cancel();
    await super.close();
  }
}

void main() {
  test(
    'application observer drains real subscriptions before SDK disposal',
    () async {
      final previous = Bloc.observer;
      final shutdown = AppShutdown();
      Bloc.observer = AppBlocObserver(shutdown: shutdown);
      addTearDown(() => Bloc.observer = previous);
      final source = StreamController<int>.broadcast();
      final order = <String>[];
      final subscriber = _Subscriber(source.stream, order);
      source.add(1);
      await Future<void>.delayed(Duration.zero);
      expect(subscriber.state, 1);
      await shutdown.stopConsumers();
      order.add('sdk disposed');
      source.add(2);
      await Future<void>.delayed(Duration.zero);
      expect(order, ['event', 'cancel', 'sdk disposed']);
      expect(subscriber.isClosed, isTrue);
      await source.close();
    },
  );
  test('a consumer failure prevents disposal and can be retried', () async {
    final shutdown = AppShutdown();
    var fail = true;
    var disposed = false;
    shutdown.register('producer', () {
      if (fail) throw StateError('offline');
    });
    await expectLater(
      shutdown.stopConsumers().then((_) => disposed = true),
      throwsStateError,
    );
    expect(disposed, isFalse);
    fail = false;
    await shutdown.stopConsumers().then((_) => disposed = true);
    expect(disposed, isTrue);
  });
}
