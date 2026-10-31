import 'dart:ui' as ui;

import 'package:flutter/foundation.dart'
    show LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../game/board_geometry.dart';
import 'game_theme.dart';
import 'board_material.dart';

/// 한 번 디코딩한 작은 스프라이트를 Flutter 연출과 Flame이 공유한다.
abstract final class StarArt {
  static const forest = 'assets/art/star_courier/night_forest.png';
  static const courier = 'assets/art/star_courier/courier.png';
  static const restingCourier = 'assets/art/star_courier/courier_rest.png';
  static const portal = 'assets/art/star_courier/star_portal.png';
  static const echo = 'assets/art/star_courier/echo.png';
  static const boardFrame = 'assets/art/star_courier/board_frame.png';
  static const riq = 'assets/art/last_echo/riq.png';
  static const riqHappy = 'assets/art/last_echo/riq_happy.png';
  static const riqThinking = 'assets/art/last_echo/riq_thinking.png';
  static const riqSurprised = 'assets/art/last_echo/riq_surprised.png';
  static const riqSleep = 'assets/art/last_echo/riq_sleep.png';
  static const runeStone = 'assets/art/last_echo/rune_stone.png';
  static const lunabel = 'assets/art/last_echo/lunabel.png';

  /// riq.png 안의 두 눈 중심(정규화)과 반지름. 잠든 얼굴 그림이 없을 때 쓴다.
  static const riqEyes = [Offset(.380, .582), Offset(.645, .585)];
  static const riqEyeRadius = Size(.040, .042);
  static final revision = ValueNotifier(0);
  static ui.Image? courierImage;
  static ui.Image? portalImage;
  static ui.Image? echoImage;
  static ui.Image? forestImage;
  static ui.Image? riqImage, runeImage;

  /// 인트로 표정. 없으면 기본 얼굴로 그린다.
  static ui.Image? riqHappyImage, riqSurprisedImage, riqSleepImage;
  static Future<void>? _loading;
  static bool _licensesRegistered = false;
  static final Map<String, ui.Image> portraits = {};
  static Future<void> loadPortrait(String path) async {
    if (portraits.containsKey(path)) return;
    final data = await rootBundle.load(path);
    final codec = await ui.instantiateImageCodec(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      targetWidth: 384,
    );
    try {
      portraits[path] = (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
  }

  static Future<void> load() {
    if (!_licensesRegistered) {
      _licensesRegistered = true;
      LicenseRegistry.addLicense(() async* {
        for (final name in ['Jua', 'NanumGothic']) {
          yield LicenseEntryWithLineBreaks([
            name,
          ], await rootBundle.loadString('assets/fonts/$name-OFL.txt'));
        }
      });
    }
    if (riqImage != null &&
        runeImage != null &&
        echoImage != null &&
        portalImage != null &&
        forestImage != null &&
        courierImage != null) {
      return Future.value();
    }
    return _loading ??= _load();
  }

  static Future<void> _load() async {
    Future<ui.Image> decode(String asset) async {
      final data = await rootBundle.load(asset);
      final codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        targetWidth: 384,
      );
      try {
        return (await codec.getNextFrame()).image;
      } finally {
        codec.dispose();
      }
    }

    try {
      courierImage = await decode(courier);
      riqImage = await decode(riq);
      runeImage = await decode(runeStone);
      portalImage = await decode(portal);
      echoImage = await decode('assets/art/last_echo/echo.png');
      forestImage = await decode(forest);
      revision.value++;
    } catch (error) {
      // 그림 준비 실패가 조작이나 기록 로딩을 막지 않는다.
      _loading = null;
      debugPrint('Star courier artwork unavailable: $error');
      return;
    }
    // 표정은 하나씩 따로 읽어 하나가 없어도 나머지 그림에 영향을 주지 않는다.
    Future<ui.Image?> optional(String asset) async {
      try {
        return await decode(asset);
      } catch (_) {
        return null;
      }
    }

    riqHappyImage ??= await optional(riqHappy);
    riqSurprisedImage ??= await optional(riqSurprised);
    riqSleepImage ??= await optional(riqSleep);
    revision.value++;
  }

  static void draw(
    Canvas canvas,
    ui.Image image,
    Rect rect, {
    double opacity = 1,
    Color? tint,
  }) {
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      rect,
      Paint()
        ..filterQuality = FilterQuality.medium
        ..color = Colors.white.withValues(alpha: opacity)
        ..colorFilter = tint == null
            ? null
            : ColorFilter.mode(tint, BlendMode.srcATop),
    );
  }
}

class CourierPortrait extends StatelessWidget {
  const CourierPortrait({
    super.key,
    this.height = 140,
    this.label,
    this.resting = false,
  });
  final double height;
  final String? label;
  final bool resting;

  @override
  Widget build(BuildContext context) => Image.asset(
    StarArt.riq,
    height: height,
    width: resting ? height * 1.5 : height,
    fit: BoxFit.contain,
    cacheWidth: resting ? 768 : 512,
    semanticLabel: label,
    excludeFromSemantics: label == null,
  );
}

/// 테두리는 좌표계 밖에 둔다. 그림이 가장자리 정령이나 터치를 덮지 않는다.
class StarBoardFrame extends StatelessWidget {
  const StarBoardFrame({super.key, required this.child, this.geometry});
  final Widget child;
  final BoardGeometry? geometry;
  @override
  Widget build(BuildContext context) {
    final layout = geometry;
    // Production provides geometry; this fallback keeps standalone widget previews usable.
    if (layout == null) {
      return Padding(
        padding: const EdgeInsets.all(BoardGeometry.defaultFrameInset),
        child: child,
      );
    }
    return RepaintBoundary(
      child: CustomPaint(
        painter: MoonstoneFramePainter(layout, GameTheme.colorsOf(context)),
        child: Padding(
          padding: EdgeInsets.all(layout.frameInset),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(layout.boardRadius),
            child: child,
          ),
        ),
      ),
    );
  }
}
