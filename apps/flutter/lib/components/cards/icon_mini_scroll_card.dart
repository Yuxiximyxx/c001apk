import 'package:c001apk_flutter/components/network_image.dart';
import 'package:flutter/material.dart';

import '../../components/self_sized_horizontal_list.dart';
import '../../components/source_container.dart';
import '../../logic/model/feed/entity.dart';
import '../../utils/extensions.dart';
import '../../utils/miuix_palette.dart';
import '../../utils/utils.dart';

class IconMiniScrollCard extends StatelessWidget {
  const IconMiniScrollCard({super.key, required this.dataList});

  final List<Entity> dataList;

  @override
  Widget build(BuildContext context) {
    return SelfSizedHorizontalList(
      gapSize: 10,
      padding: null,
      itemCount: dataList.length,
      childBuilder: (index) {
        return miniCardItem(
          context,
          dataList[index].logo ?? dataList[index].pic.orEmpty,
          dataList[index].title.orEmpty,
          dataList[index].url.orEmpty,
          false,
          false,
        );
      },
    );
  }
}

Widget miniCardItem(
  BuildContext context,
  String logo,
  String title,
  String url,
  bool isSurface,
  bool isGrid, {
  double paddingH = 6,
}) {
  double radius = isGrid ? 0.0 : 8.0;
  final color = isSurface
      ? Theme.of(context).colorScheme.surface
      : isGrid
          ? Colors.transparent
          : Theme.of(context).colorScheme.onInverseSurface;
  Widget chip(VoidCallback? onTap) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(radius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: paddingH, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              clipNetworkImage(
                logo,
                radius: 4,
                height: 18,
                width: 18,
                fit: BoxFit.cover,
              ),
              const SizedBox(width: 4),
              Flexible(
                flex: 1,
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Topic / product / user / app chips grow into their page. Feed chips
  // keep the legacy link handling so a reading pane can still claim them.
  final target = anchoredPageForUrl(url, needConvert: true, includeFeed: false);
  if (target == null) {
    return chip(() => Utils.onOpenLink(url, title, true, context));
  }
  return AnchoredContainer(
    closedColor: color,
    openColor: miuixPageBackground(context),
    closedShape: RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(radius)),
    ),
    closedBuilder: (context, open) => chip(open),
    openBuilder: (context, close) => target,
  );
}
