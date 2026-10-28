import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

Widget networkImage(
  String imageUrl, {
  BoxFit? fit,
  Alignment alignment = Alignment.center,
  double? width,
  double? height,
  bool isAvatar = false,
  ImageWidgetBuilder? imageBuilder,
  BorderRadiusGeometry? borderRadius =
      const BorderRadius.all(Radius.circular(12)),
}) {
  Widget placeHolder(BuildContext context) {
    return Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.outline.withOpacity(0.25),
        borderRadius: borderRadius,
      ),
      child: Icon(
        isAvatar ? Icons.person : Icons.all_inclusive,
        color: Theme.of(context).colorScheme.outline,
        size: width != null && width < 35
            ? width - 5
            : width != null && width < 70
                ? width - 10
                : 45,
      ),
    );
  }

  final uri = Uri.tryParse(imageUrl);
  if (uri == null ||
      !['http', 'https'].contains(uri.scheme) ||
      uri.host.isEmpty) {
    return Builder(builder: placeHolder);
  }

  // miuix23 滚动帧率：按显示尺寸解码（memCache 尺寸 = 逻辑尺寸 ×
  // dpr），避免信息流里的小图/头像按原图全尺寸解码造成解码与显存
  // 压力、滑动掉帧。尺寸未知（未传或无限宽）时不限制，保持原行为。
  return Builder(builder: (context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return CachedNetworkImage(
      fit: fit,
      alignment: alignment,
      width: width,
      height: height,
      memCacheWidth:
          width != null && width.isFinite ? (width * dpr).round() : null,
      memCacheHeight:
          height != null && height.isFinite ? (height * dpr).round() : null,
      imageUrl: imageUrl,
      imageBuilder: imageBuilder,
      placeholder: (context, url) => placeHolder(context),
      errorWidget: (context, url, error) => placeHolder(context),
      fadeOutDuration: const Duration(milliseconds: 200),
      fadeInDuration: const Duration(milliseconds: 200),
    );
  });
}

Widget clipNetworkImage(
  String imageUrl, {
  BoxFit? fit,
  double? radius,
  double? width,
  double? height,
  bool isAvatar = false,
  ImageWidgetBuilder? imageBuilder,
  BorderRadiusGeometry? clipBorderRadius,
}) {
  return ClipRRect(
    borderRadius:
        clipBorderRadius ?? BorderRadius.circular(isAvatar ? 50 : radius ?? 12),
    child: networkImage(
      imageUrl,
      fit: fit,
      width: width,
      height: height,
      isAvatar: isAvatar,
      imageBuilder: imageBuilder,
      borderRadius: null,
    ),
  );
}
