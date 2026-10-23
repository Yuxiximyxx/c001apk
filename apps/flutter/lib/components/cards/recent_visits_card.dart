import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:get/get.dart';

import '../../components/cards/message_third_card.dart';
import '../../components/network_image.dart';
import '../../logic/model/feed/datum.dart';
import '../../logic/network/network_repo.dart';
import '../../logic/state/loading_state.dart';
import '../../pages/ffflist/ffflist_page.dart' show FFFListType;
import '../../utils/extensions.dart';
import '../../utils/utils.dart';

/// 「我的常去」区块：直接在「我的」页内嵌展示最近访问的前几条；
/// 加载中/失败/为空时退回原来的单行入口，保证行为不回退。
class RecentVisitsCard extends StatefulWidget {
  const RecentVisitsCard({super.key, required this.refreshSignal});

  /// 下拉刷新时递增，触发重新拉取。
  final ValueListenable<int> refreshSignal;

  @override
  State<RecentVisitsCard> createState() => _RecentVisitsCardState();
}

class _RecentVisitsCardState extends State<RecentVisitsCard> {
  List<Datum>? _items;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    widget.refreshSignal.addListener(_fetch);
    _fetch();
  }

  @override
  void dispose() {
    widget.refreshSignal.removeListener(_fetch);
    super.dispose();
  }

  Future<void> _fetch() async {
    try {
      final state = await NetworkRepo.getDataListFromUrl(
        url: '/v6/user/recentHistoryList',
        data: {'page': 1},
      );
      if (!mounted) return;
      if (state is Success) {
        final all = (state.response as List).cast<Datum>();
        final recent =
            all.where((d) => d.entityType == 'recentHistory').toList();
        setState(() {
          _items = (recent.isNotEmpty ? recent : all).take(5).toList();
          _loading = false;
        });
      } else {
        setState(() {
          _items = null;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _items = null;
          _loading = false;
        });
      }
    }
  }

  void _openAll() {
    Get.toNamed(
      '/ffflist',
      arguments: {'type': FFFListType.RECENT},
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    if (_loading || items == null || items.isEmpty) {
      return messageThirdCard(
        context,
        0xFF00bcd4,
        Icons.my_location,
        '我的常去',
        null,
        _openAll,
      );
    }
    final colors = MiuixTheme.of(context).colors;
    return MiuixCard(
      cornerRadius: 24,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: _openAll,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      '我的常去',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(
                    '查看全部',
                    style: TextStyle(fontSize: 13, color: colors.primary),
                  ),
                  Icon(Icons.keyboard_arrow_right,
                      size: 18, color: colors.primary),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: colors.dividerLine),
          for (final data in items)
            InkWell(
              onTap: () => Utils.onOpenLink(data.url.orEmpty, data.title),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    clipNetworkImage(
                      data.logo.orEmpty,
                      isAvatar: data.targetType == 'user',
                      radius: 8,
                      width: 40,
                      height: 40,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        data.targetTypeTitle.isNullOrEmpty
                            ? data.title.orEmpty
                            : '${data.targetTypeTitle}: ${data.title}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
