import 'dart:async';

import 'package:c001apk_flutter/utils/android_links.dart';
import 'package:c001apk_flutter/utils/utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('app.awavenue.c001apk/links');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<String> pending;
  setUp(() {
    pending = ['coolmarket://feed/123?s=share#reply'];
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'takePendingLinks');
      final result = List<String>.of(pending);
      pending.clear();
      return result;
    });
  });
  tearDown(() {
    channel.setMethodCallHandler(null);
    messenger.setMockMethodCallHandler(channel, null);
    Get.reset();
  });

  Future<void> notify(WidgetTester tester) async {
    unawaited(messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec()
            .encodeMethodCall(const MethodCall('linksChanged')),
        (_) {}));
    await tester.pumpAndSettle();
  }

  testWidgets('a malformed external link cannot discard the next valid link',
      (tester) async {
    pending = ['https://www.coolapk.com/t/%FF', 'coolmarket://feed/123'];
    final links = AndroidLinks(onOpen: Utils.onOpenLink)..listen();
    await tester.pumpWidget(GetMaterialApp(
        initialRoute: '/',
        builder: FlutterSmartDialog.init(),
        getPages: [
          GetPage(name: '/', page: () => const Scaffold(body: Text('主页'))),
          GetPage(
              name: '/feed/:id',
              page: () => Scaffold(body: Text('动态 ${Get.parameters['id']}'))),
        ]));
    await tester.pumpAndSettle();
    final reading = links.ready();
    // Attach an error listener immediately so the old parsing failure is
    // reported by an assertion rather than escaping the test framework.
    Object? error;
    unawaited(reading.catchError((Object e) {
      error = e;
    }));
    await tester.pumpAndSettle();
    expect(error, isNull);
    expect(find.text('动态 123'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'cold link waits for root, warm links navigate and remain repeatable',
      (tester) async {
    final links = AndroidLinks(onOpen: Utils.onOpenLink)..listen();
    // Notifications before the navigator exists must retain the cold link.
    await notify(tester);
    expect(pending, hasLength(1));
    await tester.pumpWidget(GetMaterialApp(initialRoute: '/', getPages: [
      GetPage(name: '/', page: () => const Scaffold(body: Text('主页'))),
      GetPage(
          name: '/feed/:id',
          page: () => Scaffold(body: Text('动态 ${Get.parameters['id']}'))),
    ]));
    await tester.pumpAndSettle();
    unawaited(links.ready());
    await tester.pumpAndSettle();
    expect(find.text('动态 123'), findsOneWidget);
    Get.back();
    await tester.pumpAndSettle();
    expect(find.text('主页'), findsOneWidget);
    for (final url in [
      'https://m.coolapk.com/feed/456?s=x',
      'coolmarket://feed/123'
    ]) {
      pending.add(url);
      await notify(tester);
      expect(
          find.text(url.contains('456') ? '动态 456' : '动态 123'), findsOneWidget);
      Get.back();
      await tester.pumpAndSettle();
      expect(find.text('主页'), findsOneWidget);
    }
    expect(pending, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
