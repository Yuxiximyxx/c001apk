import 'package:c001apk_flutter/components/network_image.dart';
import 'package:flutter/material.dart';

import '../../components/html_text.dart';
import '../../components/source_container.dart';
import '../../logic/model/feed/datum.dart';
import '../../utils/date_util.dart';
import '../../utils/extensions.dart';
import '../../utils/miuix_palette.dart';
import '../../utils/utils.dart';

class LikeCard extends StatelessWidget {
  const LikeCard({super.key, required this.data});

  final Datum data;

  @override
  Widget build(BuildContext context) {
    return Ink(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onInverseSurface,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              UserAvatarContainer(
                uid: data.likeUserInfo?.uid?.toString() ?? '',
                child: clipNetworkImage(
                  data.likeUserInfo?.userAvatar ?? '',
                  isAvatar: true,
                  width: 30,
                  height: 30,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(flex: 1, child: Text(data.likeUserInfo?.username ?? '')),
              Text(
                DateUtil.fromToday(data.likeTime),
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.outline,
                ),
              )
            ],
          ),
          const SizedBox(height: 10),
          Text('赞了你的${data.infoHtml}'),
          const SizedBox(height: 10),
          _quotedFeed(context),
        ],
      ),
    );
  }

  Widget _quotedFeed(BuildContext context) {
    final color = Theme.of(context).colorScheme.surface;
    Widget block(VoidCallback? onTap) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              if (!data.pic.isNullOrEmpty) ...[
                clipNetworkImage(
                  data.pic!,
                  radius: 8,
                  width: 30,
                  height: 30,
                  fit: BoxFit.cover,
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                flex: 1,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '@${data.username}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 5),
                    htmlText(data.message ?? '', fontSize: 13),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    final target = anchoredPageForUrl(data.url ?? '');
    if (target == null) {
      return block(() => Utils.onOpenLink(data.url ?? ''));
    }
    return AnchoredContainer(
      closedColor: color,
      openColor: miuixPageBackground(context),
      closedShape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
      closedBuilder: (context, open) => block(open),
      openBuilder: (context, close) => target,
    );
  }
}
