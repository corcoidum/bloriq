import 'dart:async';

import 'package:flutter/material.dart';

import '../design/arcade_components.dart';
import '../design/game_theme.dart';
import '../domain/puzzle.dart';
import '../l10n/app_localizations.dart';
import '../settings/game_settings.dart';
import 'experience_dialogs.dart';
import 'intro_screen.dart';
import 'game_session.dart';
import '../story/companion_view.dart';
import '../story/spirit_album.dart';
import '../constellation/constellation_atlas.dart';
import 'level_picker.dart';
import 'play_context.dart';
import '../daily/daily_panel.dart';

class AppEntry extends StatefulWidget {
  const AppEntry({
    super.key,
    required this.settings,
    required this.gameBuilder,
    this.loadLevels,
    this.clock,
    this.playtestMode = const bool.fromEnvironment('PLAYTEST_MODE'),
    this.firstRunIntro = true,
  });
  final GameSettings settings;
  final DateTime Function()? clock;
  final bool playtestMode;

  /// 처음 실행한 사용자에게만 인트로를 한 번 보여 준 뒤 튜토리얼로 잇는다.
  final bool firstRunIntro;
  final Future<List<Level>> Function()? loadLevels;
  final Widget Function(GameSession session, int levelId, PlayContext play)
  gameBuilder;

  @override
  State<AppEntry> createState() => _AppEntryState();
}

class _AppEntryState extends State<AppEntry> with WidgetsBindingObserver {
  bool _entryResolved = false;
  bool _startingTutorial = false;
  bool _introPlaying = false;
  bool _failed = false;
  bool _opening = false;
  bool _loading = false;
  bool _choosing = false;
  GameSession? _session;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  Future<void> _load() async {
    if (_loading) return;
    _loading = true;
    try {
      final session = await GameSession.load(
        loadLevels: widget.loadLevels,
        clock: widget.clock,
        onOnboardingReady: (onboarding) {
          if (mounted && !_entryResolved) {
            setState(() {
              _entryResolved = true;
              _startingTutorial = onboarding.pending;
              // 'unseen'만 해당한다. 튜토리얼을 열면 inProgress가 되어 다시 나오지 않는다.
              _introPlaying =
                  widget.firstRunIntro && onboarding.status == 'unseen';
            });
          }
        },
      );
      if (!mounted) {
        unawaited(session.dispose());
        return;
      }
      setState(() {
        _session = session;
        _loading = false;
      });
      if (!session.levels.any((level) => level.id == 1)) {
        _startingTutorial = false;
      }
      _startTutorial();
    } catch (_) {
      if (mounted) {
        setState(() {
          _failed = true;
          _loading = false;
        });
      }
    }
  }

  void _introFinished() {
    if (!mounted || !_introPlaying) return;
    setState(() => _introPlaying = false);
    _startTutorial();
  }

  void _startTutorial() {
    final session = _session;
    // 인트로가 끝날 때 다시 호출되므로 그동안은 튜토리얼을 열지 않는다.
    if (_introPlaying ||
        session == null ||
        (widget.playtestMode && !session.analytics.consentKnown)) {
      return;
    }
    if (session.onboarding.pending &&
        session.levels.any((level) => level.id == 1)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _open(
            1,
            play: const PlayContext.campaign(guided: true),
            userInitiated: false,
          );
        }
      });
    }
  }

  Future<void> _consent(bool value) async {
    final session = _session;
    if (session == null) return;
    await session.analytics.setEnabled(value);
    if (mounted) {
      setState(() {});
      _startTutorial();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) setState(() {});
  }

  void _retry() {
    if (_loading) return;
    setState(() => _failed = false);
    _load();
  }

  Future<void> _open(
    int levelId, {
    PlayContext play = const PlayContext.campaign(),
    bool userInitiated = true,
  }) async {
    final session = _session;
    if (_opening || session == null) return;
    setState(() {
      _opening = true;
      _startingTutorial = false;
    });
    session.audio.setGameVisible(true);
    if (userInitiated) session.audio.onUserInteraction();
    final transition =
        !userInitiated || prefersReducedMotion(context, widget.settings)
        ? Duration.zero
        : GameEffects.panelDuration;
    try {
      await Navigator.of(context).push<void>(
        PageRouteBuilder<void>(
          transitionDuration: transition,
          reverseTransitionDuration: transition,
          pageBuilder: (_, animation, secondaryAnimation) =>
              widget.gameBuilder(session, levelId, play),
          transitionsBuilder: (_, animation, secondaryAnimation, child) =>
              FadeTransition(opacity: animation, child: child),
        ),
      );
    } finally {
      session.audio.setGameVisible(false);
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _chooseLevel() async {
    final session = _session;
    if (session == null || _opening || _choosing) return;
    _choosing = true;
    try {
      final id = await showLevelPicker(
        context,
        session,
        widget.settings,
        currentLevelId: session.nextLevelId,
      );
      if (id != null && mounted) await _open(id);
    } finally {
      _choosing = false;
    }
  }

  Future<void> _album() async {
    if (_session == null) return;
    await showSpiritAlbum(context, _session!, widget.settings);
    if (mounted) setState(() {});
  }

  Future<void> _atlas() async {
    final session = _session;
    if (session == null || _opening || _choosing) return;
    _choosing = true;
    try {
      final id = await showConstellationAtlas(
        context,
        session,
        widget.settings,
      );
      if (id != null && mounted) await _open(id);
    } finally {
      _choosing = false;
    }
  }

  Future<void> _help() async {
    final replay = await showGameHelp(context, widget.settings);
    final session = _session;
    if (replay == true && mounted && session != null) {
      await _open(
        1,
        play: PlayContext.tutorialReplay(
          session.levels.firstWhere((level) => level.id == 1),
        ),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_session?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_entryResolved) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (widget.playtestMode &&
        _session != null &&
        !_session!.analytics.consentKnown) {
      final t = AppLocalizations.of(context)!;
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    t.playtestTitle,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  Text(t.playtestPrivacy),
                  const SizedBox(height: 24),
                  FilledButton(
                    key: const ValueKey('consent-accept'),
                    onPressed: () => _consent(true),
                    child: Text(t.playtestConsent),
                  ),
                  TextButton(
                    key: const ValueKey('consent-decline'),
                    onPressed: () => _consent(false),
                    child: Text(t.playWithoutRecording),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    // 레벨과 기록은 인트로가 도는 동안 뒤에서 계속 불러온다.
    if (_introPlaying) {
      return IntroScreen(settings: widget.settings, onFinished: _introFinished);
    }
    if (_startingTutorial && !_failed) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final t = AppLocalizations.of(context)!;
    final colors = GameTheme.colorsOf(context);
    final session = _session;
    return Scaffold(
      key: const ValueKey('home-screen'),
      body: ArcadeBackdrop(
        child: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: SingleChildScrollView(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 560),
                padding: const EdgeInsets.all(GameSpacing.page),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: BrandMark(),
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: t.help,
                          onPressed: _help,
                          icon: const Icon(Icons.help_outline_rounded),
                        ),
                        IconButton(
                          tooltip: t.settings,
                          onPressed: session == null
                              ? null
                              : () => showExperienceSettings(
                                  context,
                                  widget.settings,
                                  session.audio,
                                  resumeGame: false,
                                  analytics: session.analytics,
                                ),
                          icon: const Icon(Icons.tune_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      t.lastEchoTitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 38,
                        fontFamily: GameTypography.canvasFontFamily,
                        height: 1.15,
                        color: colors.rewardInk,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      t.homeSubtitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: colors.secondaryText,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 12),
                    JourneyCompanions(
                      companion: session?.collection.companion,
                      reduceMotion: prefersReducedMotion(
                        context,
                        widget.settings,
                      ),
                      onAlbum: session == null ? null : _album,
                    ),
                    if (session != null) ...[
                      Text(
                        session.recommendedChapter.name.inLocale(t.localeName),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        t.seasonProgress(session.collection.owned.length),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        t.chapterCollection(
                          session.recommendedChapter.name.inLocale(
                            t.localeName,
                          ),
                          session.collection
                              .inChapter(session.recommendedChapter.number)
                              .length,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value:
                            session.completedInChapter(
                              session.recommendedChapter.number,
                            ) /
                            5,
                      ),
                      if (session.collection.owned.length == 25)
                        Text(t.seasonComplete, textAlign: TextAlign.center),
                    ],
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      key: const ValueKey('home-play'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(48, 62),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 16,
                        ),
                      ),
                      onPressed: session == null || _opening
                          ? null
                          : () => _open(session.nextLevelId),
                      icon: const Icon(Icons.play_arrow_rounded, size: 27),
                      label: Text(
                        session == null
                            ? t.preparingGame
                            : t.playLevel(session.nextLevelId),
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 21),
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (session != null)
                      Semantics(
                        label: t.homeProgress,
                        child: Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 16,
                          runSpacing: 8,
                          children: [
                            Text(
                              t.completedLevels(
                                session.completedCount,
                                session.levels.length,
                              ),
                              style: TextStyle(color: colors.secondaryText),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.star_rounded,
                                  size: 18,
                                  color: colors.rewardInk,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  t.collectedStars(session.totalStars),
                                  style: TextStyle(color: colors.rewardInk),
                                ),
                              ],
                            ),
                          ],
                        ),
                      )
                    else if (_failed)
                      Column(
                        children: [
                          Text(t.loadError),
                          TextButton.icon(
                            key: const ValueKey('retry-load'),
                            onPressed: _retry,
                            icon: const Icon(Icons.refresh_rounded),
                            label: Text(t.retry),
                          ),
                        ],
                      )
                    else
                      const LinearProgressIndicator(),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      key: const ValueKey('home-levels'),
                      onPressed: session == null || _opening
                          ? null
                          : _chooseLevel,
                      icon: const Icon(Icons.route_rounded),
                      label: Text(t.journeyMap),
                    ),
                    if (session != null) ...[
                      OutlinedButton.icon(
                        key: const ValueKey('home-album'),
                        onPressed: _album,
                        icon: const Icon(Icons.auto_stories_outlined),
                        label: Text(t.album),
                      ),
                      const SizedBox(height: GameSpacing.small),
                      OutlinedButton.icon(
                        key: const ValueKey('home-atlas'),
                        onPressed: _opening ? null : _atlas,
                        icon: const Icon(Icons.auto_awesome),
                        label: Text(t.constellationAtlas),
                      ),
                      if (session.collection.backfillPending)
                        ArcadeSurface(
                          child: Column(
                            children: [
                              Text(t.backfillUpdated),
                              TextButton(
                                key: const ValueKey('dismiss-backfill'),
                                onPressed: () async {
                                  await session.collection
                                      .acknowledgeBackfill();
                                  if (mounted) setState(() {});
                                },
                                child: Text(t.backfillDismiss),
                              ),
                            ],
                          ),
                        ),
                      if (session.collection.pendingIds.isNotEmpty)
                        TextButton(
                          onPressed: _album,
                          child: Text(
                            t.pendingMemories(
                              session.collection.pendingIds.length,
                            ),
                          ),
                        ),
                      CollectionStorageNotice(
                        session: session,
                        onChanged: () => setState(() {}),
                      ),
                    ],
                    const SizedBox(height: 18),
                    if (session != null &&
                        (session.progress.saveFailed ||
                            session.onboarding.saveFailed))
                      Text(t.saveError),
                    if (session != null)
                      DailyPanel(
                        daily: session.daily,
                        onPlay: _opening
                            ? null
                            : () => _open(
                                session.daily.today.level.id,
                                play: PlayContext.daily(session.daily.today),
                              ),
                      ),
                    const SizedBox(height: GameSpacing.large),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
