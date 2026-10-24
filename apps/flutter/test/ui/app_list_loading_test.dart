import 'dart:async';
import 'dart:io';

import 'package:c001apk_flutter/components/expressive_loading_indicator.dart';
import 'package:c001apk_flutter/pages/home/app/app_list_controller.dart';
import 'package:c001apk_flutter/pages/home/app/app_list_page.dart';
import 'package:c001apk_flutter/pages/home/return_top_controller.dart';
import 'package:c001apk_flutter/utils/storage_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory temp;
  late Completer<List<Map<String, String>>> installedApps;
  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('c001apk-app-list-');
    Hive.init(temp.path);
    GStorage.settings = await Hive.openBox('settings');
  });
  setUp(() {
    installedApps = Completer();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppListController.platform, (call) async {
      expect(call.method, 'getInstalledApps');
      return installedApps.future;
    });
    Get.put(ReturnTopController(), tag: 'home');
  });
  tearDown(() {
    Get.reset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppListController.platform, null);
  });
  tearDownAll(() async {
    await Hive.close();
    await temp.delete(recursive: true);
  });

  const apps = [
    {'appName': '测试应用', 'packageName': 'test.app', 'versionName': '1.0'}
  ];

  testWidgets(
      'installed apps use expressive loading until enumeration finishes',
      (tester) async {
    await tester.pumpWidget(const GetMaterialApp(home: AppListPage()));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(ExpressiveLoadingIndicator), findsOneWidget);
    installedApps.complete(apps);
    await tester.runAsync(() async {});
    await tester.pumpAndSettle();
    expect(find.text('测试应用'), findsOneWidget);
    expect(find.byType(ExpressiveLoadingIndicator), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'pull to refresh keeps installed apps visible with expressive loading',
      (tester) async {
    installedApps.complete(apps);
    await tester.pumpWidget(const GetMaterialApp(home: AppListPage()));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.runAsync(() async {});
    await tester.pumpAndSettle();
    installedApps = Completer();
    await tester.drag(find.byType(ListView), const Offset(0, 350));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(ExpressiveLoadingIndicator), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('测试应用'), findsOneWidget);
    installedApps.complete(apps);
    await tester.runAsync(() async {});
    await tester.pumpAndSettle();
    expect(find.byType(ExpressiveLoadingIndicator), findsNothing);
    expect(find.text('测试应用'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
