import 'dart:async';

import 'package:c001apk_flutter/components/network_image.dart';
import 'package:flutter/material.dart';

import '../../logic/model/feed/entity.dart';
import '../../utils/extensions.dart';
import '../../utils/utils.dart';
import '../mouse_drag_scroll.dart';

class CarouselCard extends StatefulWidget {
  const CarouselCard({super.key, required this.dataList});

  final List<Entity> dataList;

  @override
  State<CarouselCard> createState() => _CarouselCardState();
}

class _CarouselCardState extends State<CarouselCard> {
  int _currentPage = 0;
  late List<Entity> _filterList;
  late PageController _controller;
  Timer? _timer;

  @override
  void initState() {
    super.initState();

    _filterList = widget.dataList.where((item) {
      return item.url?.startsWith('http') == false;
    }).toList();

    if (_filterList.length != 1) {
      _filterList.insert(0, _filterList.last);
      _filterList.add(_filterList[1]);
    }

    _controller = PageController(initialPage: _filterList.length == 1 ? 0 : 1);
  }

  @override
  void dispose() {
    _controller.dispose();
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
        builder: (context, constraints) => SizedBox(
              // 横幅容器固定 3.4:1 宽幅比例。接口的 Entity 没有图片
              // 尺寸/比例字段，比例只能取代表值：实测一张酷安众测
              // 横幅素材约 4.48:1（截图 936×2048 里图内容 883×197px），
              // 旧版按 3:1 容器 + contain 显示，图被压在容器中央、
              // 上下各留约 19dp 空边，画面显小、整个横幅区松散。
              height: (constraints.maxWidth / 3.4).clamp(0.0, 240.0),
              child: ClipRRect(
                borderRadius: const BorderRadius.all(Radius.circular(12)),
                child: Stack(
                  alignment: AlignmentDirectional.bottomEnd,
                  children: [
                    MouseDragScroll(
                      child: PageView.builder(
                        controller: _controller,
                        itemCount: _filterList.length,
                        pageSnapping: true,
                        onPageChanged: (index) async {
                          if (_filterList.length != 1) {
                            if (index == _filterList.length - 1) {
                              _timer?.cancel();
                              _timer =
                                  Timer(const Duration(milliseconds: 500), () {
                                _controller.jumpToPage(1);
                              });
                            } else if (index == 0) {
                              _timer?.cancel();
                              _timer =
                                  Timer(const Duration(milliseconds: 500), () {
                                _controller.jumpToPage(_filterList.length - 2);
                              });
                            } else {
                              _timer?.cancel();
                            }
                            setState(
                                () => _currentPage = _filterList.length == 1
                                    ? index
                                    : index == 0
                                        ? _filterList.length - 3
                                        : index == _filterList.length - 1
                                            ? 0
                                            : index - 1);
                          }
                        },
                        itemBuilder: (context, page) {
                          return GestureDetector(
                            onTap: () => Utils.onOpenLink(
                              _filterList[page].url.orEmpty,
                              _filterList[page].title,
                              true,
                              context,
                            ),
                            child: networkImage(
                              _filterList[page].pic.orEmpty,
                              // cover 铺满容器，去掉 contain 的上下
                              // 空边。素材普遍比 3.4:1 容器更宽，居中
                              // 裁切会把左侧的角标/标题裁掉，故左对
                              // 齐：被裁掉的多是素材右侧的留白。
                              fit: BoxFit.cover,
                              alignment: Alignment.centerLeft,
                              borderRadius: null,
                            ),
                          );
                        },
                      ),
                    ),
                    if (_filterList.length != 1)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 5, right: 10),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: List.generate(
                              _filterList.length == 1
                                  ? 1
                                  : _filterList.length - 2, (index) {
                            return GestureDetector(
                              onTap: () {
                                _controller.animateToPage(
                                  index + 1,
                                  duration: const Duration(milliseconds: 255),
                                  curve: Curves.ease,
                                );
                              },
                              child: Container(
                                margin: const EdgeInsets.all(2),
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _currentPage == index
                                      ? Colors.white
                                      : Colors.white.withAlpha(128),
                                ),
                              ),
                            );
                          }),
                        ),
                      ),
                  ],
                ),
              ),
            ));
  }
}
