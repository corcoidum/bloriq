import 'package:flutter/material.dart';

import '../app/game_session.dart';
import '../design/game_theme.dart';
import '../l10n/app_localizations.dart';
import '../settings/game_settings.dart';
import '../design/arcade_components.dart';
import 'companion_view.dart';
import 'story_catalog.dart';
import 'story_share.dart';

Future<void> showSpiritAlbum(
  BuildContext context,
  GameSession session,
  GameSettings settings,
) => showDialog<void>(
  context: context,
  animationStyle: prefersReducedMotion(context, settings)
      ? AnimationStyle.noAnimation
      : null,
  builder: (_) => SpiritAlbum(
    session: session,
    reduceMotion: prefersReducedMotion(context, settings),
  ),
);

class SpiritAlbum extends StatefulWidget {
  const SpiritAlbum({
    super.key,
    required this.session,
    this.reduceMotion = false,
  });
  final GameSession session;
  final bool reduceMotion;
  @override
  State<SpiritAlbum> createState() => _SpiritAlbumState();
}

class _SpiritAlbumState extends State<SpiritAlbum> {
  bool _busy = false;
  Future<void> _detail(SpiritDefinition friend) async {
    final session = widget.session;
    if (!session.collection.owns(friend.id)) return;
    await session.collection.acknowledge(friend.id);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      animationStyle: widget.reduceMotion ? AnimationStyle.noAnimation : null,
      builder: (_) => _SpiritDetail(
        session: session,
        friend: friend,
        reduceMotion: widget.reduceMotion,
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _share() async {
    if (_busy) return;
    setState(() => _busy = true);
    await showStoryCard(
      context,
      widget.session.collection.owned,
      collection: true,
      reduceMotion: widget.reduceMotion,
    );
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!,
        colors = GameTheme.colorsOf(context),
        repo = widget.session.collection;
    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 520,
          maxHeight: MediaQuery.sizeOf(context).height * .86,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      t.album,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: t.close,
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      t.gardenProgress(repo.owned.length),
                      key: const ValueKey('album-progress'),
                      style: TextStyle(color: colors.rewardInk),
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: repo.owned.length / 5,
                      color: colors.goal,
                    ),
                    const SizedBox(height: 16),
                    CollectionStorageNotice(
                      session: widget.session,
                      onChanged: () => setState(() {}),
                    ),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final columns =
                            MediaQuery.textScalerOf(context).scale(14) > 21
                            ? 1
                            : 2;
                        final width =
                            (constraints.maxWidth - (columns - 1) * 12) /
                            columns;
                        return Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            for (final friend in widget.session.story.released)
                              SizedBox(
                                width: width,
                                child: Material(
                                  color: repo.companion?.id == friend.id
                                      ? colors.echo.withValues(alpha: .13)
                                      : colors.boardSurface.withValues(
                                          alpha: .4,
                                        ),
                                  borderRadius: BorderRadius.circular(18),
                                  clipBehavior: Clip.antiAlias,
                                  child: InkWell(
                                    key: ValueKey('spirit-${friend.id}'),
                                    onTap: repo.owns(friend.id)
                                        ? () => _detail(friend)
                                        : null,
                                    child: Semantics(
                                      label: repo.owns(friend.id)
                                          ? friend.name.inLocale(t.localeName)
                                          : '${t.unknownSpirit}, ${t.level(friend.levelId)}',
                                      child: Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            SpiritPortrait(
                                              spirit: friend,
                                              size: 96,
                                              hidden: !repo.owns(friend.id),
                                            ),
                                            Text(
                                              repo.owns(friend.id)
                                                  ? friend.name.inLocale(
                                                      t.localeName,
                                                    )
                                                  : t.unknownSpirit,
                                              textAlign: TextAlign.center,
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              t.level(friend.levelId),
                                              style: TextStyle(
                                                color: colors.secondaryText,
                                                fontSize: 12,
                                              ),
                                            ),
                                            if (repo.companion?.id == friend.id)
                                              Icon(
                                                Icons.favorite_rounded,
                                                color: colors.echoInk,
                                                size: 18,
                                              ),
                                            if (repo.pendingIds.contains(
                                              friend.id,
                                            ))
                                              Icon(
                                                Icons.auto_awesome_rounded,
                                                color: colors.rewardInk,
                                                size: 18,
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      key: const ValueKey('share-collection'),
                      onPressed: _busy || repo.owned.isEmpty ? null : _share,
                      icon: const Icon(Icons.ios_share_rounded),
                      label: Text(t.collectionCard),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpiritDetail extends StatefulWidget {
  const _SpiritDetail({
    required this.session,
    required this.friend,
    required this.reduceMotion,
  });
  final GameSession session;
  final SpiritDefinition friend;
  final bool reduceMotion;
  @override
  State<_SpiritDetail> createState() => _SpiritDetailState();
}

class _SpiritDetailState extends State<_SpiritDetail> {
  bool _busy = false;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!,
        f = widget.friend,
        repo = widget.session.collection;
    return AlertDialog(
      scrollable: true,
      title: Text(f.name.inLocale(t.localeName)),
      content: SizedBox(
        width: 340,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: SpiritPortrait(spirit: f, size: 150)),
            Text(
              t.familyForest,
              style: TextStyle(color: GameTheme.colorsOf(context).goalInk),
            ),
            Text(f.personality.inLocale(t.localeName)),
            const SizedBox(height: 12),
            Text(t.recoveredMemory, style: GameTypography.label),
            Text(f.memory.inLocale(t.localeName)),
            if (f.guardian) ...[
              const SizedBox(height: 12),
              Text(t.guardianEndingTitle, style: GameTypography.label),
              Text(t.guardianEnding),
            ],
            const SizedBox(height: 12),
            Text(t.foundAtStage(f.levelId)),
            Text(f.motion.inLocale(t.localeName)),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const ValueKey('equip-companion'),
              onPressed: repo.companion?.id == f.id
                  ? null
                  : () async {
                      await repo.equip(f.id);
                      if (mounted) setState(() {});
                    },
              icon: const Icon(Icons.favorite_rounded),
              label: Text(
                repo.companion?.id == f.id
                    ? t.equippedCompanion
                    : t.equipCompanion,
              ),
            ),
            CollectionStorageNotice(
              session: widget.session,
              onChanged: () => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t.close),
        ),
        OutlinedButton.icon(
          key: const ValueKey('share-spirit'),
          onPressed: _busy
              ? null
              : () async {
                  setState(() => _busy = true);
                  await showStoryCard(context, [
                    f,
                  ], reduceMotion: widget.reduceMotion);
                  if (mounted) setState(() => _busy = false);
                },
          icon: const Icon(Icons.ios_share_rounded),
          label: Text(t.discoveryCard),
        ),
      ],
    );
  }
}

class CollectionStorageNotice extends StatefulWidget {
  const CollectionStorageNotice({
    super.key,
    required this.session,
    required this.onChanged,
  });
  final GameSession session;
  final VoidCallback onChanged;
  @override
  State<CollectionStorageNotice> createState() =>
      _CollectionStorageNoticeState();
}

class _CollectionStorageNoticeState extends State<CollectionStorageNotice> {
  bool _busy = false;
  @override
  Widget build(BuildContext context) {
    final repo = widget.session.collection, t = AppLocalizations.of(context)!;
    if (!repo.saveFailed) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          repo.futureSchema
              ? t.collectionFuture
              : repo.corrupt
              ? t.collectionCorrupt
              : t.collectionError,
          style: TextStyle(color: GameTheme.colorsOf(context).error),
        ),
        if (!repo.futureSchema)
          TextButton(
            key: const ValueKey('retry-collection'),
            onPressed: _busy
                ? null
                : () async {
                    setState(() => _busy = true);
                    if (repo.corrupt) {
                      await repo.recover(
                        widget.session.progress.saveFailed
                            ? {}
                            : widget.session.progress.completedCampaignLevelIds,
                      );
                    } else {
                      await repo.retrySave();
                    }
                    if (mounted) {
                      setState(() => _busy = false);
                      widget.onChanged();
                    }
                  },
            child: Text(repo.corrupt ? t.restoreAlbum : t.retrySave),
          ),
      ],
    );
  }
}
