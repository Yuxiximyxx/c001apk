import 'package:c001apk_flutter/components/network_image.dart';
import 'package:flutter/material.dart';

import '../../components/cards/title_card.dart';
import '../../components/self_sized_horizontal_list.dart';
import '../../components/source_container.dart';
import '../../logic/model/feed/datum.dart';
import '../../logic/model/feed/entity.dart';
import '../../utils/extensions.dart';
import '../../utils/miuix_palette.dart';
import '../../utils/utils.dart';

class IconScrollCard extends StatelessWidget {
  const IconScrollCard({super.key, required this.data});

  final Datum data;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      double width = (constraints.maxWidth - 55) / 4.5;
      return Ink(
        padding: const EdgeInsets.only(top: 10, bottom: 5),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.onInverseSurface,
          borderRadius: const BorderRadius.all(Radius.circular(12)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!data.title.isNullOrEmpty)
              TitleCard(
                title: data.title.toString(),
                url: data.url ?? '',
                bottomPadding: 5,
              ),
            SelfSizedHorizontalList(
              gapSize: 0,
              itemCount: data.entities!.length,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              childBuilder: (index) =>
                  _scrollCardItem(context, width, data.entities![index]),
            )
          ],
        ),
      );
    });
  }

  Widget _scrollCardItem(BuildContext context, double width, Entity data) {
    Widget item(VoidCallback? onTap) {
      return InkWell(
        onTap: onTap,
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        child: Container(
          margin: const EdgeInsets.all(5),
          width: width,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              clipNetworkImage(
                data.userAvatar.orEmpty,
                isAvatar: true,
                width: width - 10,
                height: width - 10,
              ),
              const SizedBox(height: 5),
              Text(
                data.username.orEmpty,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      );
    }

    final target =
        anchoredPageForUrl(data.url.orEmpty, needConvert: true, includeFeed: false);
    if (target == null) {
      return item(() =>
          Utils.onOpenLink(data.url.orEmpty, data.title, true, context));
    }
    return AnchoredContainer(
      closedColor: Theme.of(context).colorScheme.onInverseSurface,
      openColor: miuixPageBackground(context),
      closedShape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
      closedBuilder: (context, open) => item(open),
      openBuilder: (context, close) => target,
    );
  }
}
