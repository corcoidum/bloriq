import 'dart:async';

import 'package:flutter/material.dart';

import '../design/arcade_components.dart';
import '../design/game_theme.dart';
import '../domain/puzzle.dart';
import '../l10n/app_localizations.dart';
import '../settings/game_settings.dart';
import 'experience_dialogs.dart';
import 'game_session.dart';
import 'intro_screen.dart';
import 'level_picker.dart';
import 'play_context.dart';

class AppEntry extends StatefulWidget {
  const AppEntry({
    super.key,
    required this.settings,
    required this.gameBuilder,
    this.loadLevels,
  });
  final GameSettings settings;
  final Future<List<Level>> Function()? loadLevels;
  final Widget Function(GameSession session, int levelId, PlayContext play)
  gameBuilder;

  @override
  State<AppEntry> createState() => _AppEntryState();
}

class _AppEntryState extends State<AppEntry> {
  bool _intro = false;
  bool _entryResolved = false;
  bool _failed = false;
  bool _opening = false;
  bool _loading = false;
  bool _choosing = false;
  GameSession? _session;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_loading) return;
    _loading = true;
    try {
      final session = await GameSession.load(
        loadLevels: widget.loadLevels,
        onOnboardingReady: (onboarding) {
          if (mounted) {
            setState(() {
              _entryResolved = true;
              _intro = !onboarding.pending;
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
    } catch (_) {
      if (mounted) {
        setState(() {
          _failed = true;
          _loading = false;
        });
      }
    }
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
    final transition = prefersReducedMotion(context, widget.settings)
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
    unawaited(_session?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_entryResolved) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_intro) {
      return IntroScreen(
        settings: widget.settings,
        onFinished: () {
          if (mounted && _intro) setState(() => _intro = false);
        },
      );
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
                                ),
                          icon: const Icon(Icons.tune_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: GameSpacing.large),
                    const IntroScene(),
                    Text(
                      t.homeTagline,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800, height: 1.35),
                    ),
                    const SizedBox(height: GameSpacing.large),
                    ArcadeSurface(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t.homeProgress,
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(color: colors.secondaryText),
                          ),
                          const SizedBox(height: 12),
                          if (session != null) ...[
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                StatPill(
                                  icon: Icons.check_circle_outline_rounded,
                                  label: t.completedLevels(
                                    session.completedCount,
                                    session.levels.length,
                                  ),
                                  color: colors.goalInk,
                                ),
                                StatPill(
                                  icon: Icons.star_rounded,
                                  label: t.collectedStars(session.totalStars),
                                  color: colors.rewardInk,
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: LinearProgressIndicator(
                                value:
                                    session.completedCount /
                                    session.levels.length,
                                minHeight: 5,
                                color: colors.goal,
                                backgroundColor: colors.goal.withValues(
                                  alpha: .12,
                                ),
                              ),
                            ),
                          ] else if (_failed) ...[
                            Text(t.loadError),
                            TextButton.icon(
                              key: const ValueKey('retry-load'),
                              onPressed: _retry,
                              icon: const Icon(Icons.refresh_rounded),
                              label: Text(t.retry),
                            ),
                          ] else ...[
                            Text(t.preparingGame),
                            const SizedBox(height: 12),
                            const LinearProgressIndicator(),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: GameSpacing.large),
                    FilledButton.icon(
                      key: const ValueKey('home-play'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 20,
                        ),
                      ),
                      onPressed: session == null || _opening
                          ? null
                          : () => _open(session.nextLevelId),
                      icon: const Icon(Icons.play_arrow_rounded, size: 26),
                      label: Text(
                        session == null
                            ? t.preparingGame
                            : t.playLevel(session.nextLevelId),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      key: const ValueKey('home-levels'),
                      onPressed: session == null || _opening
                          ? null
                          : _chooseLevel,
                      icon: const Icon(Icons.grid_view_rounded),
                      label: Text(t.levels),
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
