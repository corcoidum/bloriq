import 'package:flutter/material.dart';

import '../design/game_theme.dart';
import '../design/star_art.dart';
import '../l10n/app_localizations.dart';
import '../postcard/echo_postcard.dart';
import 'story_catalog.dart';

/// 기존 PNG renderer/시스템 공유를 재사용한다. 소유한 친구만 전달한다.
Future<void> showStoryCard(
  BuildContext context,
  List<SpiritDefinition> friends, {
  required StoryChapter chapter,
  bool collection = false,
  bool reduceMotion = false,
}) async {
  if (friends.isEmpty) return;
  if (friends.any((s) => s.chapter != chapter.number || !s.released)) {
    throw ArgumentError('Cards must belong to one released chapter');
  }
  final t = AppLocalizations.of(context)!;
  try {
    for (final friend in friends) {
      await StarArt.loadPortrait(friend.asset!);
    }
    if (!context.mounted) return;
    final first = friends.first;
    final title = collection
        ? t.chapterCard(chapter.name.inLocale(t.localeName))
        : t.discoveryCard;
    final content = StoryCardContent(
      title: collection
          ? t.chapterCollection(
              chapter.name.inLocale(t.localeName),
              friends.length,
            )
          : first.name.inLocale(t.localeName),
      detail: collection
          ? chapter.name.inLocale(t.localeName)
          : '${chapter.name.inLocale(t.localeName)} · ${t.foundAtStage(first.levelId)}',
      quote: collection
          ? friends.length == 5
                ? chapter.ending.inLocale(t.localeName)
                : t.homeSubtitle
          : first.memory.inLocale(t.localeName),
      portraitAssets: friends.map((s) => s.asset!).toList(growable: false),
      portraitAnchors: friends
          .map((s) => s.portraitAnchor)
          .toList(growable: false),
      portraitScales: friends
          .map((s) => s.portraitScale)
          .toList(growable: false),
    );
    await showDialog<void>(
      context: context,
      animationStyle: reduceMotion || MediaQuery.disableAnimationsOf(context)
          ? AnimationStyle.noAnimation
          : null,
      builder: (_) => EchoPostcardDialog(
        data: EchoPostcardData(
          levelId: first.levelId,
          moves: 0,
          bestMoves: 0,
          stars: 1,
          levelText: title,
          movesText: '',
          bestText: '',
          story: content,
        ),
        title: title,
        shareLabel: t.shareImage,
        closeLabel: t.close,
        errorLabel: t.shareError,
      ),
    );
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(t.shareError),
          backgroundColor: GameTheme.colorsOf(context).error,
        ),
      );
    }
  }
}
