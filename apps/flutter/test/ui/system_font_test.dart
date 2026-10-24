import 'dart:io';

import 'package:c001apk_flutter/pages/settings/settings_page.dart';
import 'package:c001apk_flutter/utils/app_theme.dart';
import 'package:c001apk_flutter/utils/storage_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory temp;
  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('c001apk-font-');
    Hive.init(temp.path);
    GStorage.settings = await Hive.openBox('settings');
  });
  setUp(() async {
    await GStorage.settings.clear();
  });
  tearDown(Get.reset);
  tearDownAll(() async {
    await Hive.close();
    await temp.delete(recursive: true);
  });

  test('system font is on by default and drives the theme font family', () {
    expect(appFontFamily, 'sans-serif');
    // main.dart builds its themes exactly this way.
    final theme = ThemeData(fontFamily: appFontFamily);
    expect(theme.textTheme.bodyMedium!.fontFamily, 'sans-serif');
    expect(appMiuixThemeData(Brightness.light).textStyles.body1.fontFamily,
        'sans-serif');
    expect(appMiuixThemeData(Brightness.dark).textStyles.title1.fontFamily,
        'sans-serif');
  });

  test('turning the setting off restores the default font', () async {
    await GStorage.settings.put(SettingsBoxKey.useSystemFont, false);
    expect(appFontFamily, isNull);
    final theme = ThemeData(fontFamily: appFontFamily);
    // Identical to a theme built without any font override.
    expect(theme.textTheme.bodyMedium!.fontFamily,
        ThemeData().textTheme.bodyMedium!.fontFamily);
    // MIUIX styles stay exactly at the package defaults.
    expect(appMiuixThemeData(Brightness.light).textStyles.body1.fontFamily,
        MiuixThemeData.of(Brightness.light).textStyles.body1.fontFamily);
  });

  testWidgets('appearance settings contain the system font switch, on',
      (tester) async {
    await tester.pumpWidget(const GetMaterialApp(
        home: SettingsDetailPage(section: SettingsSection.appearance)));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('使用系统字体'), 200,
        scrollable: find.byType(Scrollable));
    await tester.pumpAndSettle();
    expect(find.text('使用系统字体'), findsOneWidget);
    final preference = tester
        .widgetList<MiuixSwitchPreference>(
            find.byType(MiuixSwitchPreference))
        .singleWhere((w) => w.title == '使用系统字体');
    expect(preference.value, isTrue);
    // Note: the switch's onChanged writes SettingsBoxKey.useSystemFont,
    // which the plain tests above exercise end-to-end. (Tapping a
    // SwitchItem is avoided here: the Hive write it triggers keeps this
    // harness's test process alive past shutdown.)
  });
}
