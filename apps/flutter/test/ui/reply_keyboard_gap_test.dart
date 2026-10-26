import 'dart:io';

import 'package:c001apk_flutter/components/glass_surface.dart';
import 'package:c001apk_flutter/pages/feed/reply/reply_page.dart';
import 'package:c001apk_flutter/utils/storage_util.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

/// Pins the reply card's floating gap on the post reply page: the
/// card's bottom edge must sit exactly 12dp above whatever is below
/// it — the screen bottom edge with no keyboard, and the keyboard's
/// top edge while the keyboard is up (miuix22: an earlier build
/// deliberately closed this gap and let the card overlap the
/// keyboard frame; real-device feedback asked for the 12dp back).
///
/// The keyboard state is simulated the way the real stack reports
/// it: `viewInsets` carries the height the panel placeholder reads,
/// and the chat_bottom_container plugin's native height callback
/// (delivered to the package over its pigeon channel) is what
/// actually switches the panel into keyboard mode.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ReplyPage reply card gap', () {
    late Directory directory;

    setUpAll(() async {
      directory = await Directory.systemTemp.createTemp('reply-gap-');
      Hive.init(directory.path);
      GStorage.settings = await Hive.openBox('settings');
    });

    tearDownAll(() async {
      await Hive.close();
      await directory.delete(recursive: true);
    });

    testWidgets('card bottom keeps a 12dp gap with and without keyboard',
        (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(400, 800);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const GetMaterialApp(home: ReplyPage()));
      // initState auto-focuses the input after 300ms; the panel
      // package only accepts keyboard heights while it has focus.
      await tester.pump(const Duration(milliseconds: 350));

      Rect cardRect() => tester.getRect(find.byType(GlassSurface));

      // No keyboard: the card floats 12dp above the bottom edge
      // (the none-state panel placeholder is viewPadding.bottom = 0
      // in the test view).
      expect(800 - cardRect().bottom, 12);

      const keyboardHeight = 280.0;
      tester.view.viewInsets = const FakeViewPadding(bottom: keyboardHeight);
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'dev.flutter.pigeon.chat_bottom_container.'
        'FSAChatBottomContainerFlutterApi.keyboardHeight',
        const StandardMessageCodec()
            .encodeMessage(<Object?>[keyboardHeight]),
        (_) {},
      );
      await tester.pump();
      // The panel container animates its size over 200ms.
      await tester.pump(const Duration(milliseconds: 300));

      // Keyboard up: still exactly 12dp between the card's bottom
      // edge and the keyboard's top edge.
      expect(800 - keyboardHeight - cardRect().bottom, 12);
    });
  });
}
