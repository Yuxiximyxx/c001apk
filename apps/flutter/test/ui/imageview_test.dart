import 'dart:ui' as ui;

import 'package:c001apk_flutter/components/app_keyboard_navigation.dart';
import 'package:c001apk_flutter/pages/others/imageview_page.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:photo_view/photo_view_gallery.dart';

const images = [
  'https://synthetic.invalid/gallery/one.png',
  'https://synthetic.invalid/gallery/two.png',
  'https://synthetic.invalid/gallery/three.png',
];

void main() {
  late String? copied;

  Future<void> open(WidgetTester tester,
      {int initialPage = 0,
      List<String> urls = images,
      Size imageSize = const Size(300, 180)}) async {
    tester.view.physicalSize = const Size(500, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final url in urls) {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(Offset.zero & imageSize, Paint()..color = Colors.blue);
      final picture = recorder.endRecording();
      final bitmap = await tester.runAsync(() =>
          picture.toImage(imageSize.width.toInt(), imageSize.height.toInt()));
      picture.dispose();
      final key = await CachedNetworkImageProvider(url)
          .obtainKey(const ImageConfiguration());
      PaintingBinding.instance.imageCache.putIfAbsent(
        key,
        () => OneFrameImageStreamCompleter(
            Future.value(ImageInfo(image: bitmap!))),
      );
    }
    await tester.pumpWidget(GetMaterialApp(
      getPages: [
        GetPage(name: '/imageview', page: () => const ImageViewPage()),
      ],
      home: const Scaffold(body: Text('合成详情页')),
      builder: (context, child) => FlutterSmartDialog(
        child: AppKeyboardNavigation(navigatorKey: Get.key, child: child!),
      ),
    ));
    await tester.pumpAndSettle();
    Get.toNamed('/imageview', arguments: {
      'imgList': urls,
      'initialPage': initialPage,
    });
    await tester.pumpAndSettle();
  }

  Finder imageFor(String url) => find.byWidgetPredicate((widget) =>
      widget is Image &&
      widget.image is CachedNetworkImageProvider &&
      (widget.image as CachedNetworkImageProvider).url == url);

  Future<void> wheel(WidgetTester tester, double delta,
      {Offset? position}) async {
    await tester.sendEventToBinding(PointerScrollEvent(
      kind: PointerDeviceKind.mouse,
      position: position ?? tester.getCenter(find.byType(ImageViewPage)),
      scrollDelta: Offset(0, delta),
    ));
    await tester.pumpAndSettle();
  }

  setUp(() {
    Get.testMode = true;
    copied = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = call.arguments['text'];
      return null;
    });
  });
  tearDown(() {
    Get.reset();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  testWidgets(
      'left and right keys switch gallery images within both boundaries',
      (tester) async {
    await open(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(find.text('1/3'), findsOneWidget);
    for (var i = 0; i < 4; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
    }
    expect(find.text('3/3'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(find.text('2/3'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('mouse wheel zooms around the pointer and clamps the scale',
      (tester) async {
    await open(tester);
    final image = imageFor(images.first);
    final before = tester.widget<Image>(image).width!;
    final imageBox = tester.renderObject<RenderBox>(image);
    final imagePoint = imageBox.size.center(Offset.zero) + const Offset(30, 0);
    final anchor = imageBox.localToGlobal(imagePoint);
    await wheel(tester, -120, position: anchor);
    expect(tester.widget<Image>(image).width, greaterThan(before));
    expect((imageBox.localToGlobal(imagePoint) - anchor).distance, lessThan(1));
    await wheel(tester, 120, position: anchor);
    expect(tester.widget<Image>(image).width, closeTo(before, 1));
    await wheel(tester, -100000);
    final largest = tester.widget<Image>(image).width!;
    expect(largest, greaterThan(before));
    // 300x180 image covering a 500x744 gallery is height constrained.
    expect(largest, lessThanOrEqualTo(744 / 180 * 8 * 300 + 1));
    await wheel(tester, -100000);
    expect(tester.widget<Image>(image).width, closeTo(largest, 1));
    await wheel(tester, 100000);
    expect(tester.widget<Image>(image).width, closeTo(before, 1));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('right click opens the existing menu for the current image',
      (tester) async {
    await open(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getCenter(find.byType(ImageViewPage)),
        kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    for (final label in ['保存图片', '保存全部图片', '分享', '复制', '在浏览器中打开']) {
      expect(find.text(label), findsOneWidget);
    }
    await tester.tap(find.text('复制'));
    await tester.pumpAndSettle();
    expect(copied, images[1]);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('image menu blocks gallery keys and Escape dismisses it first',
      (tester) async {
    await open(tester);
    await tester.tapAt(tester.getCenter(find.byType(ImageViewPage)),
        kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('1/3'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(ImageViewPage), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('2/3'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('合成详情页'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('touch swipe and long press keep working in the image viewer',
      (tester) async {
    await open(tester);
    await tester.drag(find.byType(ImageViewPage), const Offset(-380, 0));
    await tester.pumpAndSettle();
    expect(find.text('2/3'), findsOneWidget);
    await tester.longPressAt(tester.getCenter(find.byType(ImageViewPage)));
    await tester.pumpAndSettle();
    expect(find.text('保存图片'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('each image keeps its own zoom and resizing updates zoom bounds',
      (tester) async {
    await open(tester);
    final first = imageFor(images[0]);
    final fitted = tester.widget<Image>(first).width!;
    await wheel(tester, -120);
    final zoomed = tester.widget<Image>(first).width!;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(tester.widget<Image>(imageFor(images[1])).width, closeTo(fitted, 1));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(tester.widget<Image>(first).width, closeTo(zoomed, 1));
    tester.view.physicalSize = const Size(800, 500);
    await tester.pumpAndSettle();
    await wheel(tester, 100000);
    final viewport = tester.getSize(find.byType(PhotoViewGallery));
    final fitAfterResize = (viewport.width / 300 < viewport.height / 180
            ? viewport.width / 300
            : viewport.height / 180) *
        300;
    expect(tester.widget<Image>(first).width, closeTo(fitAfterResize, 1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('single image has stable boundaries and no save-all action',
      (tester) async {
    await open(tester, urls: [images.first]);
    for (final key in [
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowRight
    ]) {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
      expect(find.text('1/1'), findsOneWidget);
    }
    await tester.tapAt(tester.getCenter(find.byType(ImageViewPage)),
        kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(find.text('保存图片'), findsOneWidget);
    expect(find.text('保存全部图片'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('initial image index is clamped to the available gallery',
      (tester) async {
    await open(tester, initialPage: 99);
    expect(find.text('3/3'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(find.text('2/3'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('long images can zoom to fill the viewport width',
      (tester) async {
    await open(tester, urls: [images.first], imageSize: const Size(100, 2000));
    await wheel(tester, -100000);
    expect(tester.widget<Image>(imageFor(images.first)).width,
        greaterThanOrEqualTo(500));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
