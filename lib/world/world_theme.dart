import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class WorldPalette {
  WorldPalette.fromJson(Map<String, dynamic> data)
    : background = _color(data['background'], 'background'),
      board = _color(data['board'], 'board'),
      border = _color(data['border'], 'border'),
      accent = _color(data['accent'], 'accent'),
      accents = _accents(data['accents']);

  final ui.Color background, board, border, accent;
  final List<ui.Color> accents;

  static List<ui.Color> _accents(Object? value) {
    if (value == null) return const [];
    if (value is! List || value.length < 2) {
      throw const FormatException(
        'World accent colors need at least two colors',
      );
    }
    return List.unmodifiable(value.map((color) => _color(color, 'accents')));
  }

  static ui.Color _color(Object? value, String name) {
    if (value is! String || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(value)) {
      throw FormatException('Invalid world palette color: $name');
    }
    return ui.Color(0xff000000 | int.parse(value.substring(1), radix: 16));
  }
}

class WorldTheme {
  WorldTheme.fromJson(Map<String, dynamic> data)
    : palette = switch (data['palette']) {
        null => null,
        final Map<String, dynamic> colors => WorldPalette.fromJson(colors),
        _ => throw const FormatException('Invalid world palette'),
      },
      floor = _asset(data['floor'], 'floor'),
      woodFloor = switch (data['woodFloor']) {
        null => false,
        final bool value => value,
        _ => throw const FormatException('Invalid wood floor option'),
      },
      rock = _asset(data['rock'], 'rock'),
      bgm = _asset(data['bgm'], 'bgm');

  final WorldPalette? palette;
  final String? floor, rock, bgm;
  final bool woodFloor;

  static WorldTheme? parse(Object? data) => switch (data) {
    null => null,
    final Map<String, dynamic> theme => WorldTheme.fromJson(theme),
    _ => throw const FormatException('Invalid world theme'),
  };

  static String? _asset(Object? value, String name) {
    if (value == null) return null;
    if (value is! String ||
        !value.startsWith('assets/') ||
        value.length == 'assets/'.length ||
        value.trim() != value) {
      throw FormatException('Invalid world theme asset: $name');
    }
    return value;
  }

  Future<WorldBoardSkin> loadBoardSkin() async {
    final images = await Future.wait([_loadImage(floor), _loadImage(rock)]);
    return WorldBoardSkin(
      palette: palette,
      floor: images[0],
      woodFloor: woodFloor,
      rock: images[1],
    );
  }

  static Future<ui.Image?> _loadImage(String? path) async {
    if (path == null) return null;
    try {
      final bytes = await rootBundle.load(path);
      final codec = await ui.instantiateImageCodec(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
      try {
        return (await codec.getNextFrame()).image;
      } finally {
        codec.dispose();
      }
    } on Object catch (error) {
      // 그림을 읽지 못하면 팔레트나 기본 스킨으로 계속 플레이한다.
      debugPrint('World theme image unavailable: $path ($error)');
      return null;
    }
  }
}

class WorldBoardSkin {
  const WorldBoardSkin({
    this.palette,
    this.floor,
    this.rock,
    this.woodFloor = false,
  });

  final WorldPalette? palette;
  final ui.Image? floor, rock;
  final bool woodFloor;

  void dispose() {
    floor?.dispose();
    rock?.dispose();
  }
}
