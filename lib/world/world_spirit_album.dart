import 'package:flutter/material.dart';

import '../design/game_theme.dart';
import '../design/keep_all_text.dart';
import '../l10n/app_localizations.dart';
import 'world_catalog.dart';
import 'world_progress.dart';
import 'world_text.dart';

class WorldSpiritPortrait extends StatelessWidget {
  const WorldSpiritPortrait({
    super.key,
    required this.asset,
    required this.size,
  });

  final String? asset;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = GameTheme.colorsOf(context);
    final placeholder = Icon(
      Icons.star_rounded,
      color: colors.reward,
      size: size * .55,
    );
    return SizedBox.square(
      dimension: size,
      child: asset == null
          ? Center(child: placeholder)
          : Image.asset(
              asset!,
              fit: BoxFit.contain,
              cacheWidth: 512,
              excludeFromSemantics: true,
              errorBuilder: (_, _, _) => Center(child: placeholder),
            ),
    );
  }
}

class WorldSpiritAlbum extends StatelessWidget {
  const WorldSpiritAlbum({super.key, required this.atlas, required this.story});

  final WorldAtlas atlas;
  final WorldStory story;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final colors = GameTheme.colorsOf(context);
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(backgroundColor: colors.background, title: Text(t.album)),
      body: SafeArea(
        child: ListView(
          key: const ValueKey('world-spirit-list'),
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text(
              story.title.inLocale(t.localeName),
              textAlign: TextAlign.center,
              style: GameTypography.reward.copyWith(color: colors.rewardInk),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 12),
              child: Text(
                t.journeyFriends(atlas.cleared, Worlds.stageCount),
                textAlign: TextAlign.center,
                style: GameTypography.label.copyWith(
                  color: colors.secondaryText,
                ),
              ),
            ),
            for (final chapter in atlas.chapters)
              for (final stage in chapter.stages)
                _SpiritRow(stage: stage, asset: chapter.portraitFor(stage)),
          ],
        ),
      ),
    );
  }
}

class _SpiritRow extends StatelessWidget {
  const _SpiritRow({required this.stage, required this.asset});

  final WorldStageView stage;
  final String? asset;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final spirit = stage.spirit;
    final colors = GameTheme.colorsOf(context);
    final lang = t.localeName;
    final unlocked = stage.cleared;
    return Card(
      key: ValueKey('world-spirit-${spirit.id}'),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        leading: unlocked
            ? WorldSpiritPortrait(asset: asset, size: 54)
            : SizedBox.square(
                dimension: 54,
                child: Icon(Icons.star_border_rounded, color: colors.outline),
              ),
        title: Text(
          unlocked ? spirit.name.inLocale(lang) : t.unknownSpirit,
          style: GameTypography.label,
        ),
        subtitle: Text(
          '${WorldText.stage.resolve(lang)} ${Worlds.stageNumber(spirit.levelId)}',
        ),
        trailing: unlocked ? const Icon(Icons.chevron_right_rounded) : null,
        onTap: unlocked ? () => _open(context, t) : null,
      ),
    );
  }

  void _open(BuildContext context, AppLocalizations t) {
    final spirit = stage.spirit;
    final lang = t.localeName;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(spirit.name.inLocale(lang), textAlign: TextAlign.center),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            WorldSpiritPortrait(asset: asset, size: 144),
            for (final text in [spirit.appearance, spirit.memory, spirit.quote])
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: KeepAllText(
                  text.inLocale(lang),
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t.close),
          ),
        ],
      ),
    );
  }
}
