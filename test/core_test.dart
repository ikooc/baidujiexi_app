import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:baidujiexi_app/core/api_client.dart';
import 'package:baidujiexi_app/core/crypto.dart';
import 'package:baidujiexi_app/core/download_manager.dart';
import 'package:baidujiexi_app/core/models.dart';
import 'package:baidujiexi_app/core/remote_config.dart';
import 'package:baidujiexi_app/core/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('clientSign', () {
    test('produces a 24-char hex string', () {
      final sign = clientSign('secret', 'https://pan.baidu.com/s/abc');
      expect(sign.length, 24);
      expect(RegExp(r'^[0-9a-f]{24}$').hasMatch(sign), isTrue);
    });

    test('is deterministic for identical input', () {
      expect(
        clientSign('s', 'payload'),
        clientSign('s', 'payload'),
      );
    });

    test('changes when the payload changes', () {
      expect(
        clientSign('s', 'payload-a'),
        isNot(clientSign('s', 'payload-b')),
      );
    });
  });

  group('AppConfig', () {
    test('parses backend payload and normalizes trailing slashes', () {
      final config = AppConfig.fromJson(<String, dynamic>{
        'apiBase': 'https://file.mdx.wang/',
        'referer': 'https://file.mdx.wang/',
        'fallbackBases': <String>['https://mirror.example.com/'],
        'defaultMode': 'exe',
        'configVersion': 3,
      });

      expect(config.apiBase, 'https://file.mdx.wang');
      expect(config.siteOrigin, 'https://file.mdx.wang');
      expect(config.fallbackBases, <String>['https://mirror.example.com']);
      expect(config.defaultMode, 'exe');
      expect(config.allBases, <String>[
        'https://file.mdx.wang',
        'https://mirror.example.com',
      ]);
    });

    test('throws when apiBase is missing', () {
      expect(
        () => AppConfig.fromJson(<String, dynamic>{}),
        throwsA(isA<ApiException>()),
      );
    });

    test('parses the announcement field and trims whitespace', () {
      final config = AppConfig.fromJson(<String, dynamic>{
        'apiBase': 'https://file.mdx.wang',
        'announcement': '  维护通知：今晚 23:00 起升级  ',
      });
      expect(config.announcement, '维护通知：今晚 23:00 起升级');
    });

    test('defaults announcement to empty when absent', () {
      final config = AppConfig.fromJson(<String, dynamic>{
        'apiBase': 'https://file.mdx.wang',
      });
      expect(config.announcement, '');
    });

    test('keeps unknown backend keys in extras', () {
      final config = AppConfig.fromJson(<String, dynamic>{
        'apiBase': 'https://file.mdx.wang',
        'popup': <String, dynamic>{'enabled': true, 'content': 'hello'},
      });
      // 未建模的字段必须原样保留，供调用方按 key 读取。
      final popup = config.extra<Map<String, dynamic>>('popup');
      expect(popup, isNotNull);
      expect(popup!['enabled'], isTrue);
      expect(popup['content'], 'hello');
    });

    test('extra returns null for a missing or mistyped key', () {
      final config = AppConfig.fromJson(<String, dynamic>{
        'apiBase': 'https://file.mdx.wang',
      });
      expect(config.extra<Map<String, dynamic>>('popup'), isNull);
    });

    test('toJson round-trips extras back into the payload', () {
      final config = AppConfig.fromJson(<String, dynamic>{
        'apiBase': 'https://file.mdx.wang',
        'popup': <String, dynamic>{'enabled': true},
      });
      final json = config.toJson();
      expect(json['popup'], <String, dynamic>{'enabled': true});
      // extras 只收集未知键，已知字段保持原值。
      expect(json['apiBase'], 'https://file.mdx.wang');
    });
  });

  group('DownloadStatus', () {
    test('maps engine status strings to UI status', () {
      expect(DownloadStatus.fromEngine('running'), DownloadStatus.running);
      expect(DownloadStatus.fromEngine('wait'), DownloadStatus.waiting);
      expect(DownloadStatus.fromEngine('pause'), DownloadStatus.paused);
      expect(DownloadStatus.fromEngine('error'), DownloadStatus.error);
      expect(DownloadStatus.fromEngine('done'), DownloadStatus.done);
      expect(DownloadStatus.fromEngine('ready'), DownloadStatus.ready);
    });

    test('falls back to ready for unknown engine status', () {
      expect(DownloadStatus.fromEngine('whatever'), DownloadStatus.ready);
    });

    test('exposes terminal and active flags', () {
      expect(DownloadStatus.done.isTerminal, isTrue);
      expect(DownloadStatus.error.isTerminal, isTrue);
      expect(DownloadStatus.running.isTerminal, isFalse);
      expect(DownloadStatus.running.isActive, isTrue);
      expect(DownloadStatus.waiting.isActive, isTrue);
      expect(DownloadStatus.paused.isActive, isFalse);
    });
  });

  group('DownloadItem', () {
    DownloadItem makeItem() => DownloadItem(
          gopeedId: '1',
          name: 'demo.zip',
          url: 'https://example.com/demo.zip',
        );

    test('progress is null when total size is unknown', () {
      expect(makeItem().progress, isNull);
    });

    test('progress clamps to the 0..1 range', () {
      final item = makeItem()
        ..total = 100
        ..downloaded = 40;
      expect(item.progress, closeTo(0.4, 1e-9));

      item.downloaded = 250;
      expect(item.progress, 1.0);
    });

    test('formats byte sizes with the right unit', () {
      expect(DownloadItem.formatBytes(0), '0 B');
      expect(DownloadItem.formatBytes(512), '512 B');
      expect(DownloadItem.formatBytes(2048), '2.0 KB');
      expect(DownloadItem.formatBytes(5 * 1024 * 1024), '5.0 MB');
    });

    test('builds a downloaded / total size label', () {
      final item = makeItem()..downloaded = 1024;
      expect(item.sizeLabel, '1.0 KB');

      item.total = 4096;
      expect(item.sizeLabel, '1.0 KB / 4.0 KB');
    });

    test('speed label is empty when idle', () {
      final item = makeItem();
      expect(item.speedLabel, '');

      item.speed = 1536;
      expect(item.speedLabel, '2 KB/s');

      item.speed = 3 * 1024 * 1024;
      expect(item.speedLabel, '3.0 MB/s');
    });
  });

  group('DownloadManager.fileNameFromUrl', () {
    test('prefers the outname query parameter of a Baidu direct link', () {
      expect(
        DownloadManager.fileNameFromUrl(
          'https://d.pcs.baidu.com/file/abc123?fid=1&outname=MI8_V12.zip&time=1',
        ),
        'MI8_V12.zip',
      );
    });

    test('url-decodes the outname value', () {
      expect(
        DownloadManager.fileNameFromUrl(
          'https://d.pcs.baidu.com/file/abc?outname=%E6%B5%8B%E8%AF%95.rar',
        ),
        '测试.rar',
      );
    });

    test('falls back to the last path segment when outname is absent', () {
      expect(
        DownloadManager.fileNameFromUrl('https://example.com/files/demo.zip'),
        'demo.zip',
      );
    });

    test('returns null when no name can be derived', () {
      expect(DownloadManager.fileNameFromUrl(''), isNull);
      expect(DownloadManager.fileNameFromUrl('https://example.com/'), isNull);
    });
  });

  group('normalizeShareLink', () {
    test('canonicalizes a bare share link', () {
      expect(
        normalizeShareLink('https://pan.baidu.com/s/1UgeXksswnRYgvDB_aaE3Zw'),
        'https://pan.baidu.com/s/1UgeXksswnRYgvDB_aaE3Zw',
      );
    });

    test('extracts the pwd from the pasted blob text', () {
      const blob = '通过百度网盘分享的文件：MI8_V12.zip\n'
          '链接：https://pan.baidu.com/s/1UgeXksswnRYgvDB_aaE3Zw \n'
          '提取码：vD32';
      expect(
        normalizeShareLink(blob),
        'https://pan.baidu.com/s/1UgeXksswnRYgvDB_aaE3Zw?pwd=vD32',
      );
    });

    test('keeps an existing ?pwd= in the link', () {
      expect(
        normalizeShareLink('https://pan.baidu.com/s/1abcdefghij?pwd=ab12'),
        'https://pan.baidu.com/s/1abcdefghij?pwd=ab12',
      );
    });

    test('handles the wap/init?surl= form', () {
      expect(
        normalizeShareLink(
          'https://pan.baidu.com/wap/init?surl=abcdefghij&pwd=ab12',
        ),
        'https://pan.baidu.com/s/1abcdefghij?pwd=ab12',
      );
    });

    test('returns the input unchanged when no share link is present', () {
      expect(normalizeShareLink('not a link'), 'not a link');
    });
  });

  group('StorageService', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      // path_provider 在测试环境无实现，桩掉文档目录查询。
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => Directory.systemTemp.path,
      );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        null,
      );
    });

    test('defaults to the system directory when no custom dir is set', () async {
      final dir = await StorageService.instance.resolveDir();
      expect(dir, isNotEmpty);
    });

    test('persists a writable custom dir and resolves it back', () async {
      final temp = await Directory.systemTemp.createTemp('baidujiexi-dir');
      final target = p.join(temp.path, 'custom-downloads');
      final ok = await StorageService.instance.setCustomDir(target);
      expect(ok, isTrue);
      expect(StorageService.instance.customDir, target);
      expect(await StorageService.instance.resolveDir(), target);
      await temp.delete(recursive: true);
    });

    test('rejects an empty path', () async {
      expect(await StorageService.instance.setCustomDir('   '), isFalse);
    });

    test('resetDir clears the custom dir and falls back to default', () async {
      final temp = await Directory.systemTemp.createTemp('baidujiexi-dir2');
      await StorageService.instance.setCustomDir(temp.path);
      expect(StorageService.instance.customDir, isNotNull);
      await StorageService.instance.resetDir();
      expect(StorageService.instance.customDir, isNull);
      await temp.delete(recursive: true);
    });
  });
}
