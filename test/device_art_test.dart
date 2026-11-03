// 검토용 장치 시트: flutter test test/device_art_test.dart --dart-define=CAPTURE_DEVICES=true
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bloriq/design/game_theme.dart';
import 'package:bloriq/domain/puzzle.dart';
import 'package:bloriq/game/bloriq_game.dart';
import 'package:bloriq/game/device_art.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _colors = GameColors.dark;

Future<ui.Image> _render(void Function(Canvas) draw, {int size = 100}) async {
  final recorder = ui.PictureRecorder();
  draw(Canvas(recorder));
  final picture = recorder.endRecording();
  final image = await picture.toImage(size, size);
  picture.dispose();
  return image;
}

Future<List<int>> _pixels(ui.Image image) async =>
    (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer
        .asUint8List()
        .toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every device draws visible art without any image files', () async {
    for (final kind in DeviceKind.values) {
      for (final amount in [0.0, .5, 1.0]) {
        final image = await _render(
          (c) => DeviceArt.draw(
            c,
            kind,
            const Rect.fromLTWH(0, 0, 100, 100),
            _colors,
            amount: amount,
          ),
        );
        final bytes = await _pixels(image);
        var painted = 0;
        for (var i = 3; i < bytes.length; i += 4) {
          if (bytes[i] > 0) painted++;
        }
        // 장치는 칸을 가득 채워 블록이 올라가도 테두리가 보여야 한다.
        expect(painted, greaterThan(100 * 100 * .35), reason: '$kind $amount');
        image.dispose();
      }
    }
  });

  test('gate and moonbloom look different when open', () async {
    for (final kind in [DeviceKind.gate, DeviceKind.moonbloom]) {
      Future<List<int>> at(double amount) async => _pixels(
        await _render(
          (c) => DeviceArt.draw(
            c,
            kind,
            const Rect.fromLTWH(0, 0, 100, 100),
            _colors,
            amount: amount,
          ),
        ),
      );
      expect(await at(0), isNot(orderedEquals(await at(1))));
    }
  });

  test('wind leaves point where the tile lets a block leave', () async {
    Future<List<int>> at(Offset direction) async => _pixels(
      await _render(
        (c) => DeviceArt.draw(
          c,
          DeviceKind.oneWay,
          const Rect.fromLTWH(0, 0, 100, 100),
          _colors,
          direction: direction,
        ),
      ),
    );
    final right = await at(const Offset(1, 0));
    expect(right, isNot(orderedEquals(await at(const Offset(-1, 0)))));
    expect(right, isNot(orderedEquals(await at(const Offset(0, 1)))));
  });

  test('only animated devices change over time', () async {
    for (final kind in DeviceKind.values) {
      Future<List<int>> at(double phase) async => _pixels(
        await _render(
          (c) => DeviceArt.draw(
            c,
            kind,
            const Rect.fromLTWH(0, 0, 100, 100),
            _colors,
            phase: phase,
          ),
        ),
      );
      final moving = const {
        DeviceKind.eraser,
        DeviceKind.hold,
        DeviceKind.oneWay,
      }.contains(kind);
      final same = (await at(0)).toString() == (await at(1.3)).toString();
      expect(same, !moving, reason: '$kind');
    }
  });

  test('stones differ by position but stay stable for the same tile', () async {
    Future<List<int>> at(int variant) async => _pixels(
      await _render(
        (c) => DeviceArt.draw(
          c,
          DeviceKind.wall,
          const Rect.fromLTWH(0, 0, 100, 100),
          _colors,
          variant: variant,
        ),
      ),
    );
    expect(await at(0), isNot(orderedEquals(await at(1))));
    expect(await at(1), isNot(orderedEquals(await at(2))));
    expect(await at(3), orderedEquals(await at(0)));
  });

  test('device list covers each rule on the level', () {
    final level = Level(
      id: 1,
      boardWidth: 4,
      boardHeight: 4,
      startPosition: const Position(0, 0),
      exitPosition: const Position(3, 3),
      blocks: const [],
      obstacles: const [],
      minimumMoves: 6,
      difficulty: 'test',
      echoSwitch: const Position(1, 0),
      echoGate: const Position(2, 0),
      echoErasers: {const Position(0, 1)},
      echoHolds: {const Position(1, 1)},
      oneWays: {const Position(2, 1): const Position(0, -1)},
      goalOnlyTiles: {const Position(3, 1)},
    );
    final tiles = deviceTiles(level);
    expect(tiles.map((t) => t.$2).toSet(), {
      DeviceKind.moonbloom,
      DeviceKind.gate,
      DeviceKind.eraser,
      DeviceKind.hold,
      DeviceKind.oneWay,
      DeviceKind.goalOnly,
    });
    expect(
      tiles.firstWhere((t) => t.$2 == DeviceKind.oneWay).$3,
      const Offset(0, -1),
    );
  });

  test('review sheet', () async {
    if (!const bool.fromEnvironment('CAPTURE_DEVICES')) return;
    final entries = <(DeviceKind, double)>[
      (DeviceKind.gate, 0),
      (DeviceKind.gate, 1),
      (DeviceKind.moonbloom, 0),
      (DeviceKind.moonbloom, 1),
      (DeviceKind.eraser, 0),
      (DeviceKind.hold, 0),
      (DeviceKind.oneWay, 0),
      (DeviceKind.goalOnly, 0),
      (DeviceKind.wall, 0),
    ];
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const big = 110.0, small = 48.0, gap = 12.0;
    final width = entries.length * (big + gap) + gap;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width, big + small + gap * 3),
      Paint()..color = const Color(0xff15263d),
    );
    for (var i = 0; i < entries.length; i++) {
      final x = gap + i * (big + gap);
      final (kind, amount) = entries[i];
      DeviceArt.draw(
        canvas,
        kind,
        Rect.fromLTWH(x, gap, big, big),
        _colors,
        amount: amount,
      );
      DeviceArt.draw(
        canvas,
        kind,
        Rect.fromLTWH(x + (big - small) / 2, big + gap * 2, small, small),
        _colors,
        amount: amount,
      );
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(
      width.ceil(),
      (big + small + gap * 3).ceil(),
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory('build/overhaul-captures').createSync(recursive: true);
    File('build/overhaul-captures/devices.png')
        .writeAsBytesSync(data!.buffer.asUint8List());
  });
}
