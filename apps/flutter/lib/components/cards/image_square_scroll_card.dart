import 'package:c001apk_flutter/components/network_image.dart';
import 'package:flutter/material.dart';

import '../../components/self_sized_horizontal_list.dart';
import '../../components/source_container.dart';
import '../../logic/model/feed/entity.dart';
import '../../utils/miuix_palette.dart';
import '../../utils/utils.dart';

class ImageSquareScrollCard extends StatelessWidget {
  const ImageSquareScrollCard({super.key, required this.dataList});

  final List<Entity> dataList;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      double width = (constraints.maxWidth - 40) / 5;
      return SelfSizedHorizontalList(
        gapSize: 10,
        padding: null,
        itemCount: dataList.length,
        childBuilder: (index) => _imageSquareScrollCardItem(
          context,
          width,
          dataList[index],
        ),
      );
    });
  }

  Widget _imageSquareScrollCardItem(
      BuildContext context, double width, Entity data) {
    Widget tile(VoidCallback? onTap) {
      return GestureDetector(
        onTap: onTap,
        child: Stack(
          children: [
            clipNetworkImage(
              data.pic.toString(),
              radius: 12,
              imageBuilder: (context, imageProvider) => Container(
                decoration: BoxDecoration(
                  image: DecorationImage(
                    image: imageProvider,
                    fit: BoxFit.cover,
                    colorFilter: const ColorFilter.mode(
                      Color(0x8D000000),
                      BlendMode.darken,
                    ),
                  ),
                ),
              ),
            ),
            Center(
              child: Text(
                data.title.toString(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Color(0xFFEEEEEE)),
              ),
            ),
          ],
        ),
      );
    }

    final target = anchoredPageForUrl(data.url.toString(),
        needConvert: true, includeFeed: false);
    return SizedBox(
      width: width,
      height: width,
      child: target == null
          ? tile(() =>
              Utils.onOpenLink(data.url.toString(), data.title, true, context))
          : AnchoredContainer(
              closedColor: Colors.transparent,
              openColor: miuixPageBackground(context),
              closedShape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(12)),
              ),
              closedBuilder: (context, open) => tile(open),
              openBuilder: (context, close) => target,
            ),
    );
  }
}
