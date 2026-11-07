import 'package:flutter/material.dart';

import '../app/game_session.dart';
import '../constellation/constellation_painter.dart';
import '../design/game_theme.dart';
import '../design/keep_all_text.dart';
import '../game/power_bar.dart';
import '../settings/game_settings.dart';
import 'world2_catalog.dart';
import 'world2_progress.dart';
import 'world2_text.dart';

/// 구름바다 등대 지도. 고른 스테이지 id를 돌려준다(닫으면 null).
Future<int?> showWorld2Map(
  BuildContext context,
  GameSession session,
  GameSettings settings,
) => Navigator.of(context).push<int>(
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => World2Map(session: session),
  ),
);

class World2Map extends StatefulWidget {
  const World2Map({super.key, required this.session});
  final GameSession session;

  @override
  State<World2Map> createState() => _World2MapState();
}

class _World2MapState extends State<World2Map> {
  late final World2Atlas _atlas = widget.session.world2Atlas!;
  late final PageController _pages = PageController(
    initialPage: World2.chapterOf(_atlas.nextLevelId) - 1,
  );

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = GameTheme.colorsOf(context);
    final lang = Localizations.localeOf(context).languageCode;
    final story = widget.session.world2Story!;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        title: Text(
          story.title.inLocale(lang),
          style: GameTypography.reward.copyWith(color: colors.rewardInk),
        ),
        leading: IconButton(
          key: const ValueKey('world2-close'),
          tooltip: World2Text.close.resolve(lang),
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: KeepAllText(
                story.prologue.inLocale(lang),
                textAlign: TextAlign.center,
                style: GameTypography.body.copyWith(
                  fontSize: 13.5,
                  color: colors.secondaryText,
                ),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pages,
                children: [
                  for (final chapter in _atlas.chapters)
                    _ChapterPage(chapter: chapter, lang: lang),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: FilledButton.icon(
                key: const ValueKey('world2-continue'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: () => Navigator.of(context).pop(_atlas.nextLevelId),
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(
                  '${World2Text.play.resolve(lang)} · '
                  '${World2Text.stage.resolve(lang)} '
                  '${_atlas.nextLevelId - World2.firstLevelId + 1}',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChapterPage extends StatelessWidget {
  const _ChapterPage({required this.chapter, required this.lang});
  final World2ChapterView chapter;
  final String lang;

  @override
  Widget build(BuildContext context) {
    final colors = GameTheme.colorsOf(context);
    final info = chapter.chapter;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Text(
            '${info.number}. ${info.name.inLocale(lang)}',
            style: GameTypography.reward.copyWith(
              fontSize: 20,
              color: colors.rewardInk,
            ),
          ),
          Text(
            info.constellation.inLocale(lang),
            style: GameTypography.label.copyWith(color: colors.goalInk),
          ),
          if (info.power case final power?)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    PowerBar.iconFor(power),
                    size: 16,
                    color: colors.rewardInk,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    powerDefinition(power)?.name.resolve(lang) ?? power.id,
                    style: GameTypography.label.copyWith(
                      color: colors.rewardInk,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: Semantics(
              label: info.constellation.inLocale(lang),
              value: '${chapter.cleared} / ${chapter.stages.length}',
              child: CustomPaint(
                size: Size.infinite,
                painter: ConstellationPainter(
                  definition: chapter.definition,
                  lit: chapter.lit,
                  colors: colors,
                  golden: chapter.golden ? 1 : 0,
                ),
              ),
            ),
          ),
          KeepAllText(
            !chapter.unlocked
                ? World2Text.chapterLocked.resolve(lang)
                : chapter.complete
                ? '${info.endingTitle.inLocale(lang)} — '
                      '${info.ending.inLocale(lang)}'
                : info.intro.inLocale(lang),
            textAlign: TextAlign.center,
            style: GameTypography.body.copyWith(fontSize: 13.5),
          ),
          const SizedBox(height: 8),
          for (final stage in chapter.stages)
            _StageTile(stage: stage, lang: lang),
        ],
      ),
    );
  }
}

class _StageTile extends StatelessWidget {
  const _StageTile({required this.stage, required this.lang});
  final World2StageView stage;
  final String lang;

  @override
  Widget build(BuildContext context) {
    final colors = GameTheme.colorsOf(context);
    final number = stage.level.id - World2.firstLevelId + 1;
    final spirit = stage.spirit;
    final title = stage.cleared
        ? '${spirit.levelTitle.inLocale(lang)} · ${spirit.name.inLocale(lang)}'
        : stage.unlocked
        ? spirit.levelTitle.inLocale(lang)
        : World2Text.lockedStage.resolve(lang);
    final tag = stage.level.requiredPowers.isNotEmpty
        ? World2Text.requiresPower.resolve(lang)
        : World2Text.bareHandedPossible.resolve(lang);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          key: ValueKey('world2-stage-${stage.level.id}'),
          borderRadius: BorderRadius.circular(14),
          onTap: stage.unlocked
              ? () => Navigator.of(context).pop(stage.level.id)
              : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 28,
                    child: Text(
                      '$number',
                      style: GameTypography.label.copyWith(
                        color: stage.unlocked
                            ? colors.goalInk
                            : colors.secondaryText,
                      ),
                    ),
                  ),
                  Icon(
                    !stage.unlocked
                        ? Icons.lock_rounded
                        : spirit.guardian
                        ? Icons.star_rounded
                        : Icons.cloud_rounded,
                    size: 18,
                    color: colors.secondaryText,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GameTypography.body.copyWith(fontSize: 14),
                        ),
                        if (stage.unlocked)
                          Text(
                            tag,
                            style: GameTypography.label.copyWith(
                              fontSize: 11,
                              color: colors.secondaryText,
                            ),
                          ),
                      ],
                    ),
                  ),
                  for (var star = 0; star < 3; star++)
                    Icon(
                      star < stage.stars
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      size: 16,
                      color: colors.reward,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
