import 'dart:io';

import 'package:c001apk_flutter/components/settings/app_icon_item.dart';
import 'package:c001apk_flutter/utils/app_icon_util.dart';
import 'package:c001apk_flutter/utils/storage_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppIconVariant', () {
    test('fromId parses known ids and falls back to standard', () {
      expect(AppIconVariant.fromId('default'), AppIconVariant.standard);
      expect(AppIconVariant.fromId('green'), AppIconVariant.coolGreen);
      expect(AppIconVariant.fromId('unknown'), AppIconVariant.standard);
      expect(AppIconVariant.fromId(null), AppIconVariant.standard);
      expect(AppIconVariant.fromId(''), AppIconVariant.standard);
    });

    test('ids and preview assets are distinct per variant', () {
      final ids = AppIconVariant.values.map((v) => v.id).toSet();
      final assets = AppIconVariant.values.map((v) => v.previewAsset).toSet();
      expect(ids.length, AppIconVariant.values.length);
      expect(assets.length, AppIconVariant.values.length);
    });
  });

  group('AppIconUtil channel', () {
    final calls = <MethodCall>[];

    setUp(() {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(AppIconUtil.channel, (call) async {
        calls.add(call);
        return switch (call.method) {
          'setAppIcon' => (call.arguments as Map)['variant'],
          'getAppIcon' => 'green',
          _ => null,
        };
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(AppIconUtil.channel, null);
    });

    test('applyIcon sends the variant id and parses the applied variant',
        () async {
      final applied = await AppIconUtil.applyIcon(AppIconVariant.coolGreen);
      expect(applied, AppIconVariant.coolGreen);
      expect(calls, hasLength(1));
      expect(calls.single.method, 'setAppIcon');
      expect(calls.single.arguments, {'variant': 'green'});
    });

    test('currentIcon parses the native report', () async {
      expect(await AppIconUtil.currentIcon(), AppIconVariant.coolGreen);
      expect(calls.single.method, 'getAppIcon');
    });

    test('applyIcon returns null when the platform side fails', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(AppIconUtil.channel, (call) async {
        throw PlatformException(code: 'invalid_variant');
      });
      expect(await AppIconUtil.applyIcon(AppIconVariant.coolGreen), isNull);
    });
  });

  group('AppIconItem', () {
    late Directory directory;

    setUpAll(() async {
      directory = await Directory.systemTemp.createTemp('app-icon-');
      Hive.init(directory.path);
      GStorage.settings = await Hive.openBox('settings');
    });

    tearDownAll(() async {
      await Hive.close();
      await directory.delete(recursive: true);
    });

    setUp(() async {
      await GStorage.settings.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(AppIconUtil.channel, (call) async {
        if (call.method == 'setAppIcon') {
          return (call.arguments as Map)['variant'];
        }
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(AppIconUtil.channel, null);
    });

    testWidgets('selecting the green icon applies and persists it',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: AppIconItem())),
      );
      expect(find.text('应用图标'), findsOneWidget);
      expect(find.text('当前：默认图标'), findsOneWidget);

      await tester.tap(find.text('应用图标'));
      await tester.pumpAndSettle();
      expect(find.text('默认图标'), findsOneWidget);
      expect(find.text('酷安绿'), findsOneWidget);

      await tester.tap(find.text('酷安绿'));
      await tester.pumpAndSettle();

      expect(find.text('当前：酷安绿'), findsOneWidget);
      expect(GStorage.appIcon, 'green');
      expect(GStorage.settings.get(SettingsBoxKey.appIcon), 'green');
    });

    testWidgets('stored variant drives the displayed selection',
        (tester) async {
      GStorage.setAppIcon('green');
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: AppIconItem())),
      );
      expect(find.text('当前：酷安绿'), findsOneWidget);
    });
  });
}
