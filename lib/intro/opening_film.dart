import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../art/game_art_assets.dart';
import '../audio/game_audio.dart';
import '../settings/game_settings.dart';

/// 비디오 코덱/네트워크 없이 동일한 원화 영상을 모든 플랫폼에서 재생한다.
class OpeningGate extends StatefulWidget {
  const OpeningGate({
    super.key,
    required this.enabled,
    required this.assets,
    required this.settings,
    required this.child,
  });
  final bool enabled;
  final GameArtAssets assets;
  final GameSettings settings;
  final Widget child;
  @override
  State<OpeningGate> createState() => _OpeningGateState();
}

class _OpeningGateState extends State<OpeningGate> {
  bool _finished = false;
  @override
  Widget build(BuildContext context) => !widget.enabled || _finished
      ? widget.child
      : OpeningFilm(
          assets: widget.assets,
          settings: widget.settings,
          onDone: () => setState(() => _finished = true),
        );
}

class OpeningFilm extends StatefulWidget {
  const OpeningFilm({
    super.key,
    required this.assets,
    required this.settings,
    required this.onDone,
  });
  final GameArtAssets assets;
  final GameSettings settings;
  final VoidCallback onDone;
  @override
  State<OpeningFilm> createState() => _OpeningFilmState();
}

class _OpeningFilmState extends State<OpeningFilm>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _clock =
      AnimationController(vsync: this, duration: const Duration(seconds: 12))
        ..addListener(() {
          if (mounted) setState(() {});
        })
        ..addStatusListener((status) {
          if (status == AnimationStatus.completed) unawaited(_stopSound());
        });
  AudioPlayer? _player;
  bool _ready = false, _failed = false, _started = false, _muted = false;
  bool _backgrounded = false;
  bool get _ko => Localizations.localeOf(context).languageCode == 'ko';
  bool get _reduced =>
      widget.settings.reduceMotion ||
      MediaQuery.disableAnimationsOf(context) ||
      MediaQuery.accessibleNavigationOf(context);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _failed = false);
    try {
      await widget.assets.loadCore();
      await widget.assets.prepareChapter(0);
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          _ready = true;
          _muted = !(prefs.getBool(GameAudio.musicKey) ?? true);
        });
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _stopSound() async {
    try {
      await _player?.stop();
    } catch (_) {
      /* 소리 실패는 진입을 막지 않는다. */
    }
  }

  Future<void> _sound() async {
    if (_muted || !_started || _clock.isCompleted || _backgrounded) {
      await _stopSound();
      return;
    }
    try {
      final player = _player ??= AudioPlayer();
      await player.play(
        AssetSource('audio/opening.wav'),
        volume: .45,
        position: Duration(milliseconds: (_clock.value * 12000).round()),
      );
      // 비동기 재생 요청 중 닫거나 음소거한 경우도 즉시 중지한다.
      if (!mounted || _muted || _backgrounded) await player.stop();
    } catch (_) {
      /* 브라우저 오디오 제한에도 무음 영상은 계속한다. */
    }
  }

  void _play() {
    setState(() => _started = true);
    _clock.forward();
    unawaited(_sound());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _backgrounded = state != AppLifecycleState.resumed;
    if (_backgrounded) {
      _clock.stop();
      unawaited(_stopSound());
    } else if (_started && !_clock.isCompleted && !_reduced) {
      _clock.forward();
      unawaited(_sound());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clock.dispose();
    unawaited(_player?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final done = _reduced || _clock.isCompleted;
    if (_reduced && _clock.isAnimating) {
      _clock.stop();
      unawaited(_stopSound());
    }
    final seconds = done ? 12.0 : _clock.value * 12;
    return Scaffold(
      backgroundColor: const Color(0xff121426),
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_ready)
            Center(
              child: AspectRatio(
                aspectRatio: 9 / 16,
                child: CustomPaint(
                  painter: OpeningFilmPainter(
                    assets: widget.assets,
                    seconds: !_started && !done ? 11.8 : seconds,
                    korean: _ko,
                  ),
                ),
              ),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      if (_ready && !done)
                        IconButton.filledTonal(
                          tooltip: _ko ? '음악 켜기/끄기' : 'Toggle music',
                          onPressed: () {
                            setState(() => _muted = !_muted);
                            unawaited(_sound());
                          },
                          icon: Icon(
                            _muted ? Icons.volume_off : Icons.volume_up,
                          ),
                        ),
                      const Spacer(),
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: const Color(0x99121426),
                        ),
                        onPressed: widget.onDone,
                        child: Text(_ko ? '건너뛰기' : 'Skip'),
                      ),
                    ],
                  ),
                  const Spacer(),
                  if (_failed) ...[
                    Text(
                      _ko ? '원화를 불러오지 못했어요.' : 'Could not load the artwork.',
                      style: const TextStyle(color: Colors.white),
                    ),
                    TextButton(
                      onPressed: _load,
                      child: Text(_ko ? '다시 시도' : 'Retry'),
                    ),
                  ] else if (!_ready)
                    const CircularProgressIndicator(),
                  if (_ready && (!_started || done))
                    FilledButton.icon(
                      key: const ValueKey('opening-primary'),
                      onPressed: done ? widget.onDone : _play,
                      icon: Icon(done ? Icons.auto_awesome : Icons.play_arrow),
                      label: Text(
                        done
                            ? (_ko ? '모험 시작' : 'Begin adventure')
                            : (_ko ? '이야기 시작' : 'Watch the story'),
                      ),
                    ),
                  if (_ready && _started && !done)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: LinearProgressIndicator(
                        value: _clock.value,
                        color: const Color(0xffffdf9c),
                        backgroundColor: Colors.white12,
                      ),
                    ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 앱과 MP4 내보내기가 공유하는 12초, 3막 모션 원화 타임라인.
class OpeningFilmPainter extends CustomPainter {
  OpeningFilmPainter({
    required this.assets,
    required this.seconds,
    this.korean = true,
  });
  final GameArtAssets assets;
  final double seconds;
  final bool korean;

  double _fade(double start, double end) => Curves.easeInOut.transform(
    ((seconds - start) / (end - start)).clamp(0, 1),
  );

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.scale(size.width / 720, size.height / 1280);
    const bounds = Rect.fromLTWH(0, 0, 720, 1280);
    canvas.drawColor(const Color(0xff16172b), BlendMode.src);
    final garden = assets.background(0);
    if (garden != null) {
      final zoom = 1.04 + .075 * (seconds / 12);
      canvas.save();
      canvas.translate(360, 570);
      canvas.scale(zoom);
      canvas.translate(-360 + math.sin(seconds * .18) * 7, -570);
      _image(canvas, garden, bounds, fit: BoxFit.cover);
      canvas.restore();
    }
    // 밤의 깊이와 텍스트 대비. 섬광 대신 천천히 밝아지는 기억의 빛.
    canvas.drawRect(
      bounds,
      Paint()..color = Color.fromRGBO(18, 19, 42, .42 - .16 * _fade(7, 11)),
    );
    final fog = assets.tile('decor_mist');
    if (fog != null) {
      _image(
        canvas,
        fog,
        Rect.fromLTWH(-80 + seconds * 4, 440, 900, 430),
        opacity: .22,
      );
    }
    for (var i = 0; i < 45; i++) {
      final x = (i * 113.7 + math.sin(seconds * .45 + i) * 16) % 720;
      final y = (i * 83.3 - seconds * (7 + i % 4) + 1280) % 1280;
      final alpha = (.22 + .23 * math.sin(seconds * 1.3 + i)).clamp(.05, .45);
      canvas.drawCircle(
        Offset(x, y),
        1.1 + i % 3 * .5,
        Paint()
          ..color = Color.fromRGBO(255, 225, 158, alpha)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.4),
      );
    }
    final riq = assets.spirit(null);
    final arrival = _fade(3.2, 4.6);
    final walking = _fade(4.6, 6.5);
    final riqX = 190 + walking * 100;
    final riqY = 790 - math.sin(walking * math.pi) * 17;
    if (riq != null && arrival > 0) {
      final echo = arrival * (1 - _fade(6.2, 7.6)) * _fade(4.8, 5.5);
      if (echo > 0) {
        // 실제 정령의 실루엣에 보라 오라를 남기고 안쪽은 비운다.
        final echoRect = Rect.fromLTWH(166, 790, 245, 245);
        canvas.saveLayer(
          echoRect.inflate(24),
          Paint()..color = Colors.white.withValues(alpha: echo * .65),
        );
        _image(
          canvas,
          riq,
          echoRect.inflate(7),
          silhouette: const Color(0xffc9adff),
        );
        canvas.saveLayer(
          echoRect.inflate(24),
          Paint()..blendMode = BlendMode.dstOut,
        );
        _image(canvas, riq, echoRect.deflate(4));
        canvas.restore();
        canvas.restore();
      }
      canvas.drawOval(
        Rect.fromLTWH(riqX + 50, riqY + 205, 155, 25),
        Paint()
          ..color = Colors.black.withValues(alpha: arrival * .22)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
      );
      _image(
        canvas,
        riq,
        Rect.fromLTWH(riqX, riqY, 260, 260),
        opacity: arrival,
      );
    }
    final gate = assets.tile('exit');
    final gateFade = _fade(7.1, 8.7);
    if (gate != null && gateFade > 0) {
      final center = const Offset(530, 737);
      canvas.drawCircle(
        center,
        80 + 8 * math.sin(seconds),
        Paint()
          ..color = const Color(0xffffdd99).withValues(alpha: gateFade * .23)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 40),
      );
      _image(
        canvas,
        gate,
        const Rect.fromLTWH(420, 615, 220, 250),
        opacity: gateFade,
      );
    }
    if (seconds > 6.7) {
      final p = _fade(6.7, 9);
      final at = Offset(375 + p * 155, 830 - math.sin(p * math.pi / 2) * 110);
      canvas.drawCircle(
        at,
        8,
        Paint()
          ..color = const Color(0xffffdf9a)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
      canvas.drawCircle(at, 2.5, Paint()..color = Colors.white);
    }
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x70121426), Colors.transparent, Color(0xe6121426)],
          stops: [0, .55, 1],
        ).createShader(bounds),
    );
    final titleFade = _fade(9.1, 10.6);
    if (titleFade > 0) {
      _text(
        canvas,
        'BLORIQ',
        102,
        260,
        titleFade,
        font: 'CormorantGaramond',
        spacing: 8,
      );
      _text(canvas, 'T H E   L A S T   E C H O', 21, 372, titleFade);
      _text(
        canvas,
        korean ? '마지막 잔상이, 기억을 깨운다.' : 'One last echo. A world to remember.',
        25,
        433,
        titleFade * .9,
      );
    }
    final String line;
    final double lineAlpha;
    if (seconds < 3.8) {
      line = korean
          ? '기억의 등대가 잠든 밤…'
          : 'On the night the memory lighthouse fell asleep…';
      lineAlpha = _fade(.3, 1) * (1 - _fade(3, 3.8));
    } else if (seconds < 7.8) {
      line = korean ? '작은 전령 리크의 발걸음에\n잊힌 빛의 잔상이 남았습니다.' : 'In the footsteps of a little messenger,\nan echo of forgotten light remained.';
      lineAlpha = _fade(3.8, 4.5) * (1 - _fade(7, 7.8));
    } else {
      line = korean
          ? '별문 너머,\n당신을 기다리는 기억이 있습니다.'
          : 'Beyond the star gate,\na memory is waiting for you.';
      lineAlpha = _fade(7.8, 8.6);
    }
    _text(canvas, line, 29, 1080, lineAlpha, maxWidth: 610);
    canvas.restore();
  }

  void _image(
    Canvas canvas,
    ui.Image image,
    Rect rect, {
    BoxFit fit = BoxFit.contain,
    double opacity = 1,
    Color? silhouette,
  }) => paintImage(
    canvas: canvas,
    rect: rect,
    image: image,
    fit: fit,
    opacity: opacity,
    filterQuality: FilterQuality.medium,
    colorFilter: silhouette == null
        ? null
        : ColorFilter.mode(silhouette, BlendMode.srcIn),
  );

  void _text(
    Canvas canvas,
    String text,
    double fontSize,
    double top,
    double alpha, {
    String? font,
    double? spacing,
    double maxWidth = 670,
  }) {
    if (alpha <= 0) return;
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: const Color(0xffffedcc).withValues(alpha: alpha),
          fontSize: fontSize,
          fontFamily: font ?? 'Roboto',
          letterSpacing: spacing,
          height: 1.55,
          shadows: const [Shadow(color: Color(0xcc141426), blurRadius: 14)],
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout(maxWidth: maxWidth);
    painter.paint(canvas, Offset((720 - painter.width) / 2, top));
  }

  @override
  bool shouldRepaint(OpeningFilmPainter oldDelegate) =>
      seconds != oldDelegate.seconds ||
      korean != oldDelegate.korean ||
      assets != oldDelegate.assets;
}
