import 'dart:async';
import 'dart:io';

import 'package:c001apk_flutter/components/settings/app_icon_item.dart';
import 'package:c001apk_flutter/utils/app_icon_util.dart';
import 'package:c001apk_flutter/utils/storage_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

/// Waits until Hive's backend queue has fully drained.
///
/// Hive's VM backend serializes every operation (writes, clear, close)
/// through one future chain, and widget tests run in a FakeAsync zone
/// where a fire-and-forget `Box.put` (like the one `GStorage.setAppIcon`
/// issues from the selection handler) can be left pending forever: its
/// real file-I/O completion is only delivered while the real event loop
/// turns, and its continuations only run when the fake queue is flushed.
/// A write left pending that way silently deadlocks the next awaited
/// box operation (`setUp`'s clear, `tearDownAll`'s close). Cycling
/// runAsync + pump delivers the completion and flushes the chain; the
/// trailing flush, awaited from the real zone, proves the queue is
/// empty (and fails this test instead of hanging a later one if not).
Future<void> drainHiveWrites(WidgetTester tester) async {
  for (var attempt = 0; attempt < 5; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    final drained = await tester.runAsync(() async {
      try {
        await GStorage.settings.flush().timeout(
              const Duration(seconds: 3),
            );
        return true;
      } on TimeoutException {
        return false;
      }
    });
    if (drained ?? false) return;
  }
  fail('Hive write queue did not drain');
}

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

      // The selection handler persisted via a fire-and-forget Hive put
      // from this FakeAsync zone; drain it before the zone is torn down
      // (see drainHiveWrites).
      await drainHiveWrites(tester);
    });

    testWidgets('stored variant drives the displayed selection',
        (tester) async {
      // Seed the stored variant from the real async zone so the seeding
      // write itself can never be stranded in this test's FakeAsync
      // zone (see drainHiveWrites); the widget still reads the stored
      // value when it builds.
      await tester.runAsync(() async {
        GStorage.setAppIcon('green');
        await GStorage.settings.flush();
      });
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: AppIconItem())),
      );
      expect(find.text('当前：酷安绿'), findsOneWidget);
    });
  });
}
