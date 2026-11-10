import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:web_dex/app_config/app_config.dart';
import 'package:web_dex/blocs/update_bloc.dart';
import 'package:web_dex/services/app_update_service/app_update_service.dart';
import 'package:web_dex/services/legal_documents/legal_document.dart';
import 'package:web_dex/services/legal_documents/legal_documents_repository.dart';
import 'package:web_dex/services/storage/base_storage.dart';
import 'package:web_dex/shared/constants.dart';

class _Memory extends Fake implements BaseStorage {
  final values = <String, dynamic>{};
  @override
  Future<dynamic> read(String key) async => values[key];
  @override
  Future<bool> write(String key, dynamic value) async {
    values[key] = value;
    return true;
  }
}

class _Bundled extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(File(key).readAsBytesSync());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'community documents do not use upstream cache or make remote requests',
    () async {
      final storage = _Memory();
      storage.values['legal_document_privacy_notice'] = {
        'markdown': '# Gleec Global Privacy Notice',
      };
      storage.values['lcc_next_legal_document_privacy_notice'] = {
        'markdown': '# Wrong cached notice',
      };
      var calls = 0;
      final repo = LegalDocumentsRepository(
        storage: storage,
        assetBundle: _Bundled(),
        httpClient: MockClient((_) async {
          calls++;
          return http.Response('unexpected', 500);
        }),
      );
      addTearDown(repo.dispose);
      await repo.refreshConsentDocuments();
      for (final document in LegalDocumentType.values) {
        final content = await repo.loadPreferredContent(document);
        expect(content.source, LegalDocumentSource.bundledAsset);
        expect(content.markdown, contains('LitecoinCash DEX Next'));
        expect(
          content.markdown,
          isNot(contains('Gleec Global Privacy Notice')),
        );
        expect(await repo.refreshFromRemote(document), isNull);
      }
      expect(calls, 0);
      expect(storage.values['legal_document_privacy_notice'], isNotNull);
    },
  );

  test(
    'old upstream acceptance cannot cover the new community documents',
    () async {
      final storage = _Memory();
      final legacy = {
        'terms_version': 999,
        'accepted_at': '2026-01-01T00:00:00Z',
        'surface': 'old-upstream',
        'document_shas': <String, String>{},
      };
      storage.values['legal_acceptance_v1'] = legacy;
      final repo = LegalDocumentsRepository(
        storage: storage,
        assetBundle: _Bundled(),
      );
      addTearDown(repo.dispose);
      expect(await repo.hasAcceptedCurrentTerms(), isFalse);
      await repo.recordAcceptance(surface: 'lcc-login');
      expect(await repo.hasAcceptedCurrentTerms(), isTrue);
      expect(storage.values['legal_acceptance_v1'], same(legacy));
      expect(
        storage.values[LegalDocumentsRepository.acceptanceStorageKey],
        isNotNull,
      );
      expect(kCurrentTermsVersion, greaterThan(1));
    },
  );

  test(
    'explicit remote legal source rejects HTTP and embedded credentials',
    () async {
      for (final url in [
        'http://legal.example.invalid/doc',
        'https://user:secret@legal.example.invalid/doc',
      ]) {
        var calls = 0;
        final repo = LegalDocumentsRepository(
          storage: _Memory(),
          assetBundle: _Bundled(),
          remoteDocumentUri: (_) => Uri.parse(url),
          httpClient: MockClient((_) async {
            calls++;
            return http.Response('', 200);
          }),
        );
        expect(await repo.refreshFromRemote(LegalDocumentType.eula), isNull);
        expect(calls, 0);
        repo.dispose();
      }
    },
  );

  test(
    'community support uses the channels published by the project portal',
    () {
      expect(projectWebsiteUrl.toString(), 'https://litecoincash.com.br/');
      expect(projectCommunityUrl.path, '/comunidade');
      expect(discordInviteUrl.toString(), 'https://discord.com/invite/F2nZXnW');
      expect(
        telegramCommunityUrl.toString(),
        'https://t.me/litecoincashBrasil',
      );
      expect(redditCommunityUrl.toString(), 'https://reddit.com/r/LCCofficial');
      expect(
        twitterCommunityUrl.toString(),
        'https://twitter.com/LitecoinCash',
      );
      expect(discordSupportChannelUrl, projectCommunityUrl);
    },
  );

  test(
    'LCC is preferred without excluding or relabelling the GLEEC currency',
    () {
      expect(defaultDexCoin, 'LCC');
      expect(priorityCoinsAbbrMap['LCC'], 1000);
      expect(priorityCoinsAbbrMap['LCC-segwit'], 1000);
      expect(excludedAssetList, isNot(contains('GLEEC')));
      expect(unauthenticatedUserPriorityTickers.first, 'LCC');
    },
  );

  test(
    'unconfigured community updater cannot fetch or open an upstream release',
    () async {
      var networkClients = 0;
      var externalLaunches = 0;
      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            externalLaunches++;
            return true;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final bloc = UpdateBloc();
      addTearDown(bloc.dispose);
      await HttpOverrides.runZoned(
        () async {
          await bloc.init();
          expect(await const AppUpdateService().getUpdateInfo(), isNull);
          await bloc.update(
            const UpdateVersionInfo(
              status: UpdateStatus.required,
              version: '999.0.0',
              changelog: 'upstream fixture',
              downloadUrl:
                  'https://github.com/GLEECBTC/gleec-wallet/releases/latest',
            ),
          );
        },
        createHttpClient: (_) {
          networkClients++;
          throw StateError('Network forbidden');
        },
      );
      expect(networkClients, 0);
      expect(externalLaunches, 0);
      expect(communityAppUpdatesConfigured, isFalse);
    },
  );

  test(
    'the native icon contains real transparent PNG frames at Windows sizes',
    () {
      final bytes = File(
        'windows/runner/resources/app_icon.ico',
      ).readAsBytesSync();
      final header = ByteData.sublistView(bytes);
      expect(header.getUint16(0, Endian.little), 0);
      expect(header.getUint16(2, Endian.little), 1);
      expect(header.getUint16(4, Endian.little), 8);
      final sizes = <int>[];
      for (var i = 0; i < 8; i++) {
        final offset = 6 + i * 16;
        final size = bytes[offset] == 0 ? 256 : bytes[offset];
        final length = header.getUint32(offset + 8, Endian.little);
        final imageOffset = header.getUint32(offset + 12, Endian.little);
        expect(imageOffset + length, lessThanOrEqualTo(bytes.length));
        expect(bytes.sublist(imageOffset, imageOffset + 8), [
          137,
          80,
          78,
          71,
          13,
          10,
          26,
          10,
        ]);
        final png = ByteData.sublistView(
          bytes,
          imageOffset,
          imageOffset + length,
        );
        expect(png.getUint32(16, Endian.big), size);
        expect(png.getUint32(20, Endian.big), size);
        expect(
          bytes[imageOffset + 25],
          6,
        ); // PNG RGBA, not a flattened black square.
        sizes.add(size);
      }
      expect(sizes, [16, 20, 24, 32, 48, 64, 128, 256]);
    },
  );

  test(
    'support copy makes no upstream company or unsupported-platform claim',
    () {
      final strings =
          jsonDecode(File('assets/translations/en.json').readAsStringSync())
              as Map;
      expect(
        strings['supportInfoContent7'],
        contains('community distribution'),
      );
      expect(strings['supportInfoContent9'], contains('validated on Windows'));
      expect(strings['supportInfoContent9'], isNot(contains('iPhone')));
      expect(strings['supportDiscordButton'], 'Open Litecoin Cash Discord');
      final resource = File('windows/runner/Runner.rc').readAsStringSync();
      expect(resource, contains('"FileDescription", "LitecoinCash DEX Next"'));
      expect(resource, isNot(contains('"FileDescription", "Gleec DEX"')));
    },
  );

  test(
    'GPL text remains byte-for-byte unchanged and is included in the bundle',
    () {
      expect(
        File('assets/legal/gpl-3.0.txt').readAsBytesSync(),
        File('LICENSE').readAsBytesSync(),
      );
      expect(
        File('assets/legal/third-party-notices.md').readAsStringSync(),
        contains('Gleec'),
      );
    },
  );
}
