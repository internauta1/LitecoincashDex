import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_framework/src/exceptions/kdf_transport_exception.dart';
import 'package:komodo_defi_framework/src/native/windows_kdf_endpoint.dart';
import 'package:komodo_defi_framework/src/native/windows_tcp_ownership.dart';

typedef _NativeTable =
    Uint32 Function(
      Pointer<Void>,
      Pointer<Uint32>,
      Int32,
      Uint32,
      Int32,
      Uint32,
    );
int _wirePort(int value) => ((value & 255) << 8) | ((value >> 8) & 255);
void main() {
  group('Windows socket ownership proof', () {
    late HttpServer server;
    late WindowsTcpTableQuery api;
    late int requests;
    late List<int> snapshots;
    setUp(() async {
      api = DynamicLibrary.open('iphlpapi.dll')
          .lookupFunction<_NativeTable, WindowsTcpTableQuery>(
            'GetExtendedTcpTable',
          );
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      snapshots = [];
      requests = 0;
      server.listen((request) async {
        requests++;
        await request.drain<void>();
        request.response.write('{"result":"owned"}');
        await request.response.close();
      });
    });
    WindowsKdfEndpoint endpoint(void Function(Pointer<Uint32>, int) override) =>
        WindowsKdfEndpoint(
          Uri.http('127.0.0.1:${server.port}', '/'),
          'synthetic-test-only',
          tcpQuery: (table, size, order, af, tableClass, reserved) {
            expect(tableClass, anyOf(3, 4));
            final status = api(table, size, order, af, tableClass, reserved);
            if (table.address != 0 && status == 0) {
              snapshots.add(tableClass);
              override(table.cast<Uint32>(), tableClass);
            }
            return status;
          },
        );
    test(
      'rechecks missing listener and same connected socket before sending once',
      () async {
        final missing = {3, 4};
        final subject = endpoint((table, tableClass) {
          if (missing.remove(tableClass)) table[0] = 0;
        });
        final result = await subject.call(pid, 'version', () => true);
        expect(result, {'result': 'owned'});
        expect(requests, 1);
        expect(snapshots.take(2), [3, 3]);
        expect(
          snapshots.where((entry) => entry == 4).length,
          greaterThanOrEqualTo(2),
        );
      },
    );
    test('foreign owner after a missing listener remains a refusal', () async {
      final subject = endpoint((table, _) {
        if (snapshots.length == 1) {
          table[0] = 0;
        } else {
          table[0] = 1;
          table[1] = 2;
          table[2] = 0x0100007f;
          table[3] = _wirePort(server.port);
          table[6] = pid + 1;
        }
      });
      await expectLater(
        subject.call(pid, 'version', () => true),
        throwsA(
          isA<KdfTcpOwnershipException>().having(
            (error) => error.evidence,
            'evidence',
            KdfTcpOwnershipEvidence.foreign,
          ),
        ),
      );
      expect(snapshots, [3, 3]);
      expect(requests, 0);
    });
    test('missing connection proof never sends HTTP bytes', () async {
      final subject = endpoint((table, tableClass) {
        if (tableClass == 4) table[0] = 0;
      });
      await expectLater(
        subject.post(pid, jsonEncode({'synthetic': true}), () => true),
        throwsA(
          isA<KdfTcpOwnershipException>()
              .having(
                (error) => error.check,
                'check',
                KdfTcpOwnershipCheck.connection,
              )
              .having(
                (error) => error.evidence,
                'evidence',
                KdfTcpOwnershipEvidence.missing,
              ),
        ),
      );
      expect(snapshots.where((entry) => entry == 4), [4, 4, 4]);
      expect(requests, 0);
    });
    test('revoking the generation during a retry prevents sending', () async {
      var current = true;
      final subject = endpoint((table, tableClass) {
        if (tableClass == 4) {
          table[0] = 0;
          current = false;
        }
      });
      await expectLater(
        subject.call(pid, 'version', () => current),
        throwsA(
          isA<KdfTransportException>().having(
            (error) => error.reason,
            'reason',
            KdfTransportFailure.generationUnavailable,
          ),
        ),
      );
      expect(snapshots.where((entry) => entry == 4), [4]);
      expect(requests, 0);
    });
  }, skip: !Platform.isWindows);
}
