import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 공통 원화는 한 번 디코딩하고 Flutter/Flame/공유 카드에서 재사용한다.
/// 원본 PNG는 보존하고 런타임 디코딩 크기만 제한한다.
class GameArtAssets extends ChangeNotifier {
  GameArtAssets({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  static final shared = GameArtAssets();
  static const root = 'assets/art/moonlit';
  static const regions = [
    'garden',
    'watergate',
    'postoffice',
    'corridor',
    'observatory',
  ];
  static const tiles = [
    'frame',
    'empty',
    'blue',
    'mint',
    'obstacle',
    'exit',
    'echo',
    'ornament',
    'button',
    'decor_flowers',
    'decor_mist',
    'decor_stars',
    'decor_petals',
  ];
  static const reference = 'docs/art/moonlit-selected-reference.png';
  final AssetBundle _bundle;
  final Map<String, ui.Image> _images = {};
  final Map<String, Future<ui.Image>> _loading = {};
  int _chapter = 0;
  bool _disposed = false;
  int get chapter => _chapter;
  ui.Image? tile(String name) => _images['tiles/$name'];
  ui.Image? spirit(String? id) => _images['spirits/${id ?? 'riq'}'];
  ui.Image? background(int chapter) =>
      _images['backgrounds/${regions[chapter.clamp(0, 4)]}'];
  int get decodedImageCount => _images.length;
  int get decodedBackgroundCount =>
      _images.keys.where((key) => key.startsWith('backgrounds/')).length;

  Future<ui.Image> _load(String key, int width) {
    final ready = _images[key];
    if (ready != null) return Future.value(ready);
    return _loading.putIfAbsent(key, () async {
      try {
        final bytes = await _bundle.load('$root/$key.png');
        final codec = await ui.instantiateImageCodec(
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
          targetWidth: width,
          allowUpscaling: false,
        );
        try {
          final frame = await codec.getNextFrame();
          if (_disposed) {
            frame.image.dispose();
            throw StateError('Art cache was disposed');
          }
          _images[key] = frame.image;
          return frame.image;
        } finally {
          codec.dispose();
        }
      } finally {
        _loading.remove(key);
      }
    });
  }

  Future<void> loadCore() async {
    await Future.wait([
      for (final name in tiles)
        _load(
          'tiles/$name',
          name == 'frame'
              ? 768
              : name == 'button'
              ? 512
              : 256,
        ),
      _load('spirits/riq', 384),
    ]);
  }

  Future<ui.Image> loadSpirit(String? id) =>
      _load('spirits/${id ?? 'riq'}', 384);

  /// 지역 전환 요청 순서와 무관하게 현재+다음 두 배경만 캐시에 남긴다.
  Future<void> prepareChapter(int chapter) async {
    _chapter = chapter.clamp(0, 4);
    final requested = _chapter;
    try {
      await _load('backgrounds/${regions[requested]}', 1024);
    } finally {
      _pruneBackgrounds();
    }
    if (_disposed || _chapter != requested) return;
    notifyListeners();
    // 다음 배경 선로딩 실패는 현재 지역의 플레이를 막지 않는다.
    if (requested < 4) {
      try {
        await _load('backgrounds/${regions[requested + 1]}', 1024);
      } catch (_) {
        /* 해당 지역을 선택하면 명시적인 재시도로 복구한다. */
      } finally {
        _pruneBackgrounds();
      }
    }
  }

  void _pruneBackgrounds() {
    if (_disposed) return;
    final keep = {_chapter, if (_chapter < 4) _chapter + 1};
    for (final key
        in _images.keys
            .where((key) => key.startsWith('backgrounds/'))
            .toList()) {
      if (!keep.any((index) => key == 'backgrounds/${regions[index]}')) {
        _images.remove(key)?.dispose();
      }
    }
  }

  Future<void> prepareSpirits(Iterable<String> ids) async {
    await Future.wait(ids.toSet().map(loadSpirit));
  }

  @override
  void dispose() {
    _disposed = true;
    for (final image in _images.values) {
      image.dispose();
    }
    _images.clear();
    super.dispose();
  }
}

class GameArtScope extends InheritedWidget {
  const GameArtScope({super.key, required this.assets, required super.child});
  final GameArtAssets assets;
  static GameArtAssets? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GameArtScope>()?.assets;
  @override
  bool updateShouldNotify(GameArtScope oldWidget) => oldWidget.assets != assets;
}

/// 네이티브 이미지와 같은 Canvas 렌더링을 사용해 공유 이미지도 일치시킨다.
void paintArt(
  ui.Canvas canvas,
  ui.Image image,
  ui.Rect rect, {
  double opacity = 1,
  bool silhouette = false,
  bool darken = false,
}) {
  final paint = ui.Paint()..filterQuality = ui.FilterQuality.medium;
  paint.color = Color.fromRGBO(255, 255, 255, opacity.clamp(0, 1));
  if (silhouette) {
    paint.colorFilter = const ColorFilter.mode(
      Color(0xff858196),
      BlendMode.srcIn,
    );
  }
  if (darken) {
    paint.colorFilter = const ColorFilter.mode(
      Color(0xffccccdf),
      BlendMode.modulate,
    );
  }
  canvas.drawImageRect(
    image,
    ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
    rect,
    paint,
  );
}

/// 프레임을 늘리지 않고 실제 석재 타일 원화의 내부 질감을 패널에 사용한다.
void paintStoneSurface(
  ui.Canvas canvas,
  ui.Image image,
  ui.Rect bounds, {
  bool dark = false,
}) {
  final src = ui.Rect.fromLTWH(
    image.width * .25,
    image.height * .25,
    image.width * .5,
    image.height * .5,
  );
  final paint = ui.Paint()..filterQuality = ui.FilterQuality.medium;
  if (dark) {
    paint.colorFilter = const ColorFilter.mode(
      Color(0xff302c45),
      BlendMode.modulate,
    );
  }
  canvas.drawImageRect(image, src, bounds, paint);
}
