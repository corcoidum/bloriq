import 'package:flutter/material.dart';

import '../app/game_session.dart';
import '../design/arcade_components.dart';
import '../design/game_theme.dart';
import '../endless/endless_rules.dart';
import '../endless/endless_screen.dart';
import '../l10n/app_localizations.dart';
import '../progression/progression_rules.dart';
import '../settings/game_settings.dart';
import 'credits_screen.dart';
import 'ending_art.dart';
import 'world_catalog.dart';
import 'world_text.dart';

const endingMusicAsset = 'assets/audio/ending.wav';

Future<void> showEnding(
  BuildContext context,
  GameSession session,
  GameSettings settings, {
  bool resumeGame = false,
  String? resumeMusicTrack,
}) async {
  if (!session.sagaComplete) return;
  final audio = session.audio;
  final transition = prefersReducedMotion(context, settings)
      ? const Duration(milliseconds: 250)
      : GameEffects.panelDuration;
  audio.setMusicTrack(endingMusicAsset);
  audio.setGameVisible(true);
  audio.onUserInteraction();
  bool? voyage;
  try {
    voyage = await Navigator.of(context).push<bool>(
      PageRouteBuilder<bool>(
        transitionDuration: transition,
        reverseTransitionDuration: transition,
        pageBuilder: (_, _, _) => EndingScreen(
          session: session,
          settings: settings,
          returnToGame: resumeGame,
        ),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  } finally {
    audio.setMusicTrack(resumeMusicTrack);
    audio.setGameVisible(resumeGame);
  }
  if (voyage == true && context.mounted) {
    await showStarseaVoyage(
      context,
      session,
      settings,
      resumeGame: resumeGame,
      resumeMusicTrack: resumeMusicTrack,
    );
  }
}

enum _EndingScene {
  lightroad(9),
  ascent(10),
  firstStar(5),
  guardians(9),
  farewell(7);

  const _EndingScene(this.seconds);
  final int seconds;
}

enum _EndingPhase { playback, credits, rewards }

class EndingScreen extends StatefulWidget {
  const EndingScreen({
    super.key,
    required this.session,
    required this.settings,
    this.returnToGame = false,
  });

  final GameSession session;
  final GameSettings settings;
  final bool returnToGame;

  @override
  State<EndingScreen> createState() => _EndingScreenState();
}

class _EndingScreenState extends State<EndingScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _clock;
  var _scene = _EndingScene.lightroad;
  var _phase = _EndingPhase.playback;
  bool _saving = false;
  bool _saveFailed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _clock = AnimationController(
      vsync: this,
      duration: Duration(seconds: _scene.seconds),
      animationBehavior: AnimationBehavior.preserve,
    )..addStatusListener(_onStatus);
    _clock.forward();
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) _advance();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_phase != _EndingPhase.playback) return;
    if (state == AppLifecycleState.resumed) {
      _clock.forward();
    } else {
      _clock.stop();
    }
  }

  void _advance() {
    if (_phase != _EndingPhase.playback) return;
    if (_scene == _EndingScene.farewell) {
      _finish(_EndingPhase.credits);
      return;
    }
    setState(() => _scene = _EndingScene.values[_scene.index + 1]);
    _clock.duration = Duration(seconds: _scene.seconds);
    _clock.forward(from: 0);
  }

  void _finish(_EndingPhase phase) {
    if (_phase != _EndingPhase.playback) return;
    _clock.stop();
    widget.session.audio.setGameVisible(false);
    setState(() => _phase = phase);
    _saveEnding();
  }

  Future<void> _saveEnding() async {
    setState(() => _saving = true);
    final saved = await widget.session.progression.markEndingSeen();
    if (!mounted) return;
    setState(() {
      _saving = false;
      _saveFailed = !saved;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => switch (_phase) {
    _EndingPhase.playback => _playback(context),
    _EndingPhase.credits => CreditsScreen(
      saga: widget.session.saga,
      onContinue: () => setState(() => _phase = _EndingPhase.rewards),
    ),
    _EndingPhase.rewards => _rewards(context),
  };

  Widget _playback(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final colors = GameTheme.colorsOf(context);
    final reduced = prefersReducedMotion(context, widget.settings);
    return Scaffold(
      backgroundColor: endingNight,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const CustomPaint(painter: EndingSky()),
          if (_scene == _EndingScene.firstStar && !reduced)
            AnimatedBuilder(
              animation: _clock,
              builder: (_, _) => ColoredBox(
                color: Colors.white.withValues(
                  alpha: _brightening(_clock.value),
                ),
              ),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Column(
                children: [
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: AnimatedBuilder(
                      animation: _clock,
                      builder: (_, _) {
                        // 첫 장면에서 진입 탭과 건너뛰기가 겹치지 않도록 잠깐 기다린다.
                        final skip =
                            reduced ||
                            widget.session.progression.endingSeen ||
                            _scene != _EndingScene.lightroad ||
                            _clock.value * _scene.seconds >= 1;
                        return FilledButton.tonal(
                          key: const ValueKey('ending-skip'),
                          onPressed: skip
                              ? () => _finish(_EndingPhase.rewards)
                              : null,
                          child: Text(
                            t.endingSkip,
                            textAlign: TextAlign.center,
                          ),
                        );
                      },
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      excludeFromSemantics: true,
                      onTap: _advance,
                      child: AnimatedBuilder(
                        key: ValueKey('ending-${_scene.name}'),
                        animation: _clock,
                        builder: (context, _) => Opacity(
                          opacity: (_clock.value * _scene.seconds / .5).clamp(
                            0.0,
                            1.0,
                          ),
                          child: _sceneView(
                            context,
                            reduced ? 1 : _clock.value,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (final scene in _EndingScene.values)
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: scene == _scene ? 20 : 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: scene == _scene
                                ? colors.reward
                                : colors.outline,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                    ],
                  ),
                  TextButton(
                    key: const ValueKey('ending-next'),
                    style: TextButton.styleFrom(
                      backgroundColor: endingNight,
                      foregroundColor: colors.reward,
                    ),
                    onPressed: _advance,
                    child: Text(
                      _scene == _EndingScene.farewell
                          ? t.endingCredits
                          : t.endingNextScene,
                      textAlign: TextAlign.center,
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

  double _brightening(double progress) =>
      ((1 - (progress - .29).abs() / .28).clamp(0.0, 1.0)) * .9;

  Widget _sceneView(BuildContext context, double progress) {
    final t = AppLocalizations.of(context)!;
    final colors = GameTheme.colorsOf(context);
    final saga = widget.session.saga!;
    final brightSky =
        _scene == _EndingScene.firstStar && _brightening(progress) > .24;
    if (_scene == _EndingScene.farewell) {
      return LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 148,
                  height: 148,
                  child: CustomPaint(painter: EndingStar(ignition: 1)),
                ),
                Text(
                  t.endingFarewell,
                  textAlign: TextAlign.center,
                  style: GameTypography.reward.copyWith(
                    color: colors.text,
                    fontSize: 29,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      );
    }
    final (label, art) = switch (_scene) {
      _EndingScene.lightroad => (
        WorldText.sagaMap.resolve(t.localeName),
        CustomPaint(
          painter: EndingLightroad(saga: saga, progress: progress),
        ),
      ),
      _EndingScene.ascent => (
        t.endingAscent,
        CustomPaint(painter: EndingAscent(progress: progress)),
      ),
      _EndingScene.firstStar => (
        saga.world(Worlds.finalWorld).title.inLocale(t.localeName),
        CustomPaint(
          painter: EndingStar(
            ignition: ((progress - .22) / .37).clamp(0.0, 1.0),
            brightSky: brightSky,
          ),
        ),
      ),
      _EndingScene.guardians => (
        t.endingGuardians,
        EndingGuardians(session: widget.session, progress: progress),
      ),
      _EndingScene.farewell => throw StateError('Farewell has its own layout'),
    };
    return CustomScrollView(
      primary: false,
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 6),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: GameTypography.reward.copyWith(
                color: brightSky ? endingNight : colors.rewardInk,
              ),
            ),
          ),
        ),
        SliverFillRemaining(
          hasScrollBody: false,
          child: SizedBox(height: 224, child: art),
        ),
      ],
    );
  }

  Widget _rewards(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final colors = GameTheme.colorsOf(context);
    return Scaffold(
      backgroundColor: endingNight,
      body: CustomPaint(
        painter: const EndingSky(),
        child: SafeArea(
          child: ListView(
            key: const ValueKey('ending-rewards'),
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
            children: [
              const Center(
                child: SizedBox(
                  width: 134,
                  height: 116,
                  child: CustomPaint(painter: EndingStar(ignition: 1)),
                ),
              ),
              Text(
                t.endingComplete,
                textAlign: TextAlign.center,
                style: GameTypography.reward.copyWith(color: colors.rewardInk),
              ),
              const SizedBox(height: 16),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(
                        Icons.military_tech_rounded,
                        color: colors.reward,
                      ),
                      title: Text(
                        titleById(sagaCompletionTitleId)!.name
                            .resolve(t.localeName),
                      ),
                      subtitle: Text(t.endingTitleReward),
                    ),
                    ListTile(
                      leading: Icon(
                        Icons.auto_awesome_rounded,
                        color: colors.echoInk,
                      ),
                      title: Text(
                        trailById(TrailIds.firstStarlight)!.name
                            .resolve(t.localeName),
                      ),
                      subtitle: Text(t.endingTrailReward),
                    ),
                  ],
                ),
              ),
              if (_saveFailed) ...[
                Text(t.saveError, textAlign: TextAlign.center),
                TextButton(
                  onPressed: _saving ? null : _saveEnding,
                  child: Text(t.retrySave),
                ),
              ],
              const SizedBox(height: 16),
              if (widget.session.endlessUnlocked)
                FilledButton.icon(
                  key: const ValueKey('ending-voyage'),
                  onPressed: () => Navigator.pop(context, true),
                  icon: const Icon(Icons.sailing_rounded),
                  label: Text(
                    EndlessText.title.resolve(t.localeName),
                    textAlign: TextAlign.center,
                  ),
                ),
              OutlinedButton(
                onPressed: () => showCredits(context, widget.session.saga),
                child: Text(t.endingCredits, textAlign: TextAlign.center),
              ),
              TextButton(
                key: const ValueKey('ending-home'),
                onPressed: () => Navigator.pop(context),
                child: Text(
                  widget.returnToGame ? t.close : t.home,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
