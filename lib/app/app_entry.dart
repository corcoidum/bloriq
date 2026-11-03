import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../design/arcade_components.dart';
import '../design/game_theme.dart';
import '../domain/puzzle.dart';
import '../l10n/app_localizations.dart';
import '../settings/game_settings.dart';
import 'experience_dialogs.dart';
import 'home_view.dart';
import 'intro_screen.dart';
import 'game_session.dart';
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
    this.showIntro = true,
  });
  final GameSettings settings;
  final DateTime Function()? clock;
  final bool playtestMode;

  /// 앱을 켤 때마다 인트로 뒤 메인 화면에 도착한다. 처음은 전체, 이후는 짧은 버전.
  final bool showIntro;
  final Future<List<Level>> Function()? loadLevels;
  final Widget Function(GameSession session, int levelId, PlayContext play)
  gameBuilder;

  @override
  State<AppEntry> createState() => _AppEntryState();
}

class _AppEntryState extends State<AppEntry> with WidgetsBindingObserver {
  static const introSeenKey = 'bloriq.intro.v1';
  bool _introResolved = false;
  bool _introPlaying = false;
  bool _introSeen = false;
  bool _failed = false;
  bool _opening = false;
  bool _loading = false;
  bool _choosing = false;
  GameSession? _session;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _resolveIntro();
    _load();
  }

  Future<void> _resolveIntro() async {
    var seen = false;
    try {
      seen =
          (await SharedPreferences.getInstance()).getBool(introSeenKey) == true;
    } catch (_) {
      // 저장소를 못 읽으면 짧은 버전으로 지나가 시작을 늦추지 않는다.
      seen = true;
    }
    if (!mounted) return;
    setState(() {
      _introResolved = true;
      _introSeen = seen;
      _introPlaying = widget.showIntro;
    });
  }

  void _introEnded() {
    if (!mounted || !_introPlaying) return;
    setState(() => _introPlaying = false);
    if (!_introSeen) {
      unawaited(
        SharedPreferences.getInstance()
            .then((prefs) => prefs.setBool(introSeenKey, true))
            .catchError((_) => false),
      );
    }
  }

  Future<void> _load() async {
    if (_loading) return;
    _loading = true;
    try {
      final session = await GameSession.load(
        loadLevels: widget.loadLevels,
        clock: widget.clock,
      );
      if (!mounted) {
        unawaited(session.dispose());
        return;
      }
      setState(() {
        _session = session;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _failed = true;
          _loading = false;
        });
      }
    }
  }

  Future<void> _consent(bool value) async {
    final session = _session;
    if (session == null) return;
    await session.analytics.setEnabled(value);
    if (mounted) setState(() {});
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
    setState(() => _opening = true);
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

  /// 처음이면 가이드 1번, 아니면 첫 미완료 별문으로 간다.
  void _play() {
    final session = _session;
    if (session == null) return;
    if (session.onboarding.pending &&
        session.levels.any((level) => level.id == 1)) {
      _open(1, play: const PlayContext.campaign(guided: true));
    } else {
      _open(session.nextLevelId);
    }
  }

  Future<void> _endless() async {
    final session = _session;
    if (session == null || _opening) return;
    final level = await session.endless.currentPuzzle();
    if (!mounted) return;
    await _open(level.id, play: PlayContext.endless(level));
  }

  Future<void> _daily() async {
    final session = _session;
    if (session == null || _opening) return;
    final play = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheet) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(GameSpacing.medium),
          child: DailyPanel(
            daily: session.daily,
            onPlay: () => Navigator.pop(sheet, true),
          ),
        ),
      ),
    );
    if (play == true && mounted) {
      await _open(
        session.daily.today.level.id,
        play: PlayContext.daily(session.daily.today),
      );
    }
  }

  Future<void> _album() async {
    final session = _session;
    if (session == null) return;
    // 메뉴의 점으로 알린 복구 안내는 도감을 열면 확인한 것으로 본다.
    if (session.collection.backfillPending) {
      await session.collection.acknowledgeBackfill();
    }
    if (!mounted) return;
    await showSpiritAlbum(context, session, widget.settings);
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
    if (!_introResolved) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    // 레벨과 기록은 인트로가 도는 동안 뒤에서 계속 불러온다.
    if (_introPlaying) {
      return IntroScreen(
        settings: widget.settings,
        short: _introSeen,
        onFinished: _introEnded,
      );
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
    final session = _session;
    return HomeView(
      session: session,
      failed: _failed,
      opening: _opening,
      reduceMotion: prefersReducedMotion(context, widget.settings),
      onPlay: _play,
      onLevels: _chooseLevel,
      onAlbum: _album,
      onAtlas: _atlas,
      onDaily: _daily,
      onEndless: _endless,
      onHelp: _help,
      onSettings: () {
        if (session != null) {
          showExperienceSettings(
            context,
            widget.settings,
            session.audio,
            resumeGame: false,
            analytics: session.analytics,
          );
        }
      },
      onRetry: _retry,
      onChanged: () => setState(() {}),
    );
  }
}
