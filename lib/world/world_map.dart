import 'package:flutter/material.dart';

import '../app/game_session.dart';
import '../constellation/constellation_painter.dart';
import '../design/game_theme.dart';
import '../design/keep_all_text.dart';
import '../game/power_bar.dart';
import '../l10n/app_localizations.dart';
import '../world/saga.dart';
import 'world_catalog.dart';
import 'world_progress.dart';
import 'world_text.dart';

/// 확장 세계 지도. 고른 스테이지 id를 돌려준다(닫으면 null).
Future<int?> showWorldMap(
  BuildContext context,
  GameSession session,
  int world,
) => Navigator.of(context).push<int>(
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => WorldMap(session: session, world: world),
  ),
);

class WorldMap extends StatefulWidget {
  const WorldMap({super.key, required this.session, required this.world});
  final GameSession session;
  final int world;

  @override
  State<WorldMap> createState() => _WorldMapState();
}

class _WorldMapState extends State<WorldMap> {
  late final WorldAtlas _atlas = widget.session.worldAtlas(widget.world)!;
  late final PageController _pages = PageController(
    initialPage: Worlds.chapterOf(_atlas.nextLevelId) - 1,
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
    final story = widget.session.world(widget.world)!.story;
    final next = widget.session.saga?.next(widget.world);
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        title: Text(
          story.title.inLocale(lang),
          style: GameTypography.reward.copyWith(color: colors.rewardInk),
        ),
        leading: IconButton(
          key: const ValueKey('world-close'),
          tooltip: WorldText.close.resolve(lang),
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
            // 세계를 다 마치면 다음 세계를 한 줄로 예고한다.
            if (_atlas.complete && next != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: _NextStory(world: next, lang: lang),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: FilledButton.icon(
                key: const ValueKey('world-continue'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: () => Navigator.of(context).pop(_atlas.nextLevelId),
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(
                  '${WorldText.play.resolve(lang)} · '
                  '${WorldText.stage.resolve(lang)} '
                  '${Worlds.stageNumber(_atlas.nextLevelId)}',
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
  final WorldChapterView chapter;
  final String lang;

  static const _minSkyHeight = 48.0;

  Future<void> _openGuardian(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => _GuardianAtlasCard(chapter: chapter, lang: lang),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = GameTheme.colorsOf(context);
    final info = chapter.chapter;
    final guardian = chapter.stages.last;
    // 보통 폰에서는 별자리가 남는 높이를 채우고, 모자라면 장 전체를 스크롤한다.
    return CustomScrollView(
      key: const ValueKey('world-chapter-scroll'),
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
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
                if (guardian.cleared)
                  Tooltip(
                    message: AppLocalizations.of(context)!.constellationAtlas,
                    child: TextButton.icon(
                      key: ValueKey('world-guardian-${guardian.level.id}'),
                      onPressed: () => _openGuardian(context),
                      icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                      label: Text(info.constellation.inLocale(lang)),
                    ),
                  )
                else
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
                          powerDefinition(power)?.name.resolve(lang) ??
                              power.id,
                          style: GameTypography.label.copyWith(
                            color: colors.rewardInk,
                          ),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: _minSkyHeight),
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
                ),
                KeepAllText(
                  !chapter.unlocked
                      ? WorldText.chapterLocked.resolve(lang)
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
          ),
        ),
      ],
    );
  }
}

class _GuardianAtlasCard extends StatelessWidget {
  const _GuardianAtlasCard({required this.chapter, required this.lang});

  final WorldChapterView chapter;
  final String lang;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final colors = GameTheme.colorsOf(context);
    final spirit = chapter.stages.last.spirit;
    final info = chapter.chapter;
    final placeholder = Icon(
      Icons.star_rounded,
      size: 46,
      color: colors.reward,
    );
    return AlertDialog(
      key: ValueKey('guardian-atlas-${spirit.levelId}'),
      scrollable: true,
      title: Text(t.constellationAtlas, textAlign: TextAlign.center),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            info.constellation.inLocale(lang),
            textAlign: TextAlign.center,
            style: GameTypography.label.copyWith(color: colors.goalInk),
          ),
          SizedBox(
            width: 220,
            height: 96,
            child: CustomPaint(
              painter: ConstellationPainter(
                definition: chapter.definition,
                lit: chapter.lit,
                colors: colors,
                golden: chapter.golden ? 1 : 0,
              ),
            ),
          ),
          if (spirit.asset case final asset?)
            Image.asset(
              asset,
              width: 72,
              height: 72,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => placeholder,
            )
          else
            placeholder,
          Text(
            spirit.name.inLocale(lang),
            textAlign: TextAlign.center,
            style: GameTypography.reward.copyWith(color: colors.rewardInk),
          ),
          Text(info.familyName.inLocale(lang), textAlign: TextAlign.center),
          const SizedBox(height: 10),
          KeepAllText(
            spirit.memory.inLocale(lang),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          KeepAllText(
            spirit.quote.inLocale(lang),
            textAlign: TextAlign.center,
            style: GameTypography.body.copyWith(color: colors.goalInk),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t.close),
        ),
      ],
    );
  }
}

class _StageTile extends StatelessWidget {
  const _StageTile({required this.stage, required this.lang});
  final WorldStageView stage;
  final String lang;

  @override
  Widget build(BuildContext context) {
    final colors = GameTheme.colorsOf(context);
    final number = Worlds.stageNumber(stage.level.id);
    final spirit = stage.spirit;
    final title = stage.cleared
        ? '${spirit.levelTitle.inLocale(lang)} · ${spirit.name.inLocale(lang)}'
        : stage.unlocked
        ? spirit.levelTitle.inLocale(lang)
        : WorldText.lockedStage.resolve(lang);
    final tag = stage.level.requiredPowers.isNotEmpty
        ? WorldText.requiresPower.resolve(lang)
        : WorldText.bareHandedPossible.resolve(lang);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          key: ValueKey('world-stage-${stage.level.id}'),
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

/// 다 마친 세계 지도 아래에 붙는 다음 이야기 예고.
class _NextStory extends StatelessWidget {
  const _NextStory({required this.world, required this.lang});
  final SagaWorld world;
  final String lang;

  @override
  Widget build(BuildContext context) {
    final colors = GameTheme.colorsOf(context);
    final status = world.playable
        ? world.subtitle.inLocale(lang)
        : WorldText.comingSoon.resolve(lang);
    return Container(
      key: const ValueKey('world-next-story'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.reward.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.reward.withValues(alpha: .4)),
      ),
      child: Column(
        children: [
          Text(
            '${WorldText.nextStory.resolve(lang)} · '
            '${world.title.inLocale(lang)} · $status',
            textAlign: TextAlign.center,
            style: GameTypography.label.copyWith(color: colors.rewardInk),
          ),
          const SizedBox(height: 2),
          KeepAllText(
            world.teaser.inLocale(lang),
            textAlign: TextAlign.center,
            style: GameTypography.body.copyWith(fontSize: 13.5),
          ),
        ],
      ),
    );
  }
}
