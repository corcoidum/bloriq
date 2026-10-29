import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../art/moonlit_scene.dart';
import '../progress/progress_repository.dart';
import 'season.dart';
import 'spirit_art.dart';
import 'spirit_postcard.dart';

class CollectionDialog extends StatefulWidget {
  const CollectionDialog({
    super.key,
    required this.season,
    required this.progress,
    required this.onStage,
    required this.reduceMotion,
  });
  final Season season;
  final ProgressRepository progress;
  final ValueChanged<int> onStage;
  final bool reduceMotion;
  @override
  State<CollectionDialog> createState() => _CollectionDialogState();
}

class _CollectionDialogState extends State<CollectionDialog> {
  bool get ko => Localizations.localeOf(context).languageCode == 'ko';
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Dialog(
      child: MoonlitPaper(
        child: SizedBox(
          width: 500,
          height: MediaQuery.sizeOf(context).height * .82,
          child: DefaultTabController(
            length: 2,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          t.collection,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        tooltip: t.close,
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${widget.progress.spiritIds.length} / 25 · ${t.seasonTitle}',
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: widget.progress.spiritIds.length / 25,
                        semanticsLabel: t.collection,
                      ),
                    ],
                  ),
                ),
                TabBar(
                  tabs: [
                    Tab(text: t.collection),
                    Tab(text: t.worldMap),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [_chapters(false), _chapters(true)],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _chapters(bool map) => ListView.builder(
    padding: const EdgeInsets.all(16),
    itemCount: 5,
    itemBuilder: (context, chapter) {
      final t = AppLocalizations.of(context)!;
      final spirits = widget.season.spirits
          .where((s) => s.chapter == chapter)
          .toList();
      return Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${chapter + 1}. ${widget.season.chapterName(chapter, ko)}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (map)
              ...spirits.map(
                (s) => ListTile(
                  leading: CircleAvatar(child: Text('${s.stage}')),
                  title: Text(s.text('title', ko)),
                  subtitle: Text(
                    widget.progress.rewardStages.contains(s.stage)
                        ? '★ ${t.memoryRestored}'
                        : t.discoverSpirit,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.pop(context);
                    widget.onStage(s.stage);
                  },
                ),
              )
            else
              LayoutBuilder(
                builder: (context, c) => Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: spirits.map((s) {
                    final unlocked = widget.progress.spiritIds.contains(s.id);
                    final selected = widget.progress.companionId == s.id;
                    return SizedBox(
                      width: (c.maxWidth - 16) / 3,
                      child: Card(
                        color: selected
                            ? Theme.of(context).colorScheme.secondaryContainer
                            : null,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: unlocked ? () => _detail(s) : null,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Column(
                              children: [
                                SpiritArt(
                                  spirit: s,
                                  locked: !unlocked,
                                  size: 64,
                                  reduceMotion: widget.reduceMotion,
                                ),
                                Text(
                                  unlocked ? s.text('name', ko) : '???',
                                  textAlign: TextAlign.center,
                                ),
                                Text(
                                  selected
                                      ? t.companion
                                      : '${s.stage}${s.guardian ? ' ★' : ''}',
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
          ],
        ),
      );
    },
  );
  Future<void> _detail(Spirit s) async {
    final t = AppLocalizations.of(context)!;
    await showDialog<void>(
      context: context,
      animationStyle: widget.reduceMotion ? AnimationStyle.noAnimation : null,
      builder: (dialogContext) => AlertDialog(
        title: Text('${s.text('name', ko)}${s.guardian ? ' ★' : ''}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SpiritArt(
                spirit: s,
                size: 150,
                reduceMotion: widget.reduceMotion,
                reaction: 'welcome',
              ),
              Text(t.familyLabel(s.family)),
              Text(s.text('personality', ko)),
              const SizedBox(height: 8),
              Text(s.text('description', ko)),
              const SizedBox(height: 12),
              Text('“${s.text('memory', ko)}”'),
              const SizedBox(height: 12),
              Text(
                '${widget.season.chapterName(s.chapter, ko)} · ${t.level(s.stage)}',
              ),
              Text(s.text('motion', ko)),
              Text('“${s.text('quote', ko)}”'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(t.close),
          ),
          TextButton(
            onPressed: () => showSpiritPostcard(
              dialogContext,
              spirits: [s],
              heading: s.text('name', ko),
              subtitle:
                  '${widget.season.chapterName(s.chapter, ko)} · ${s.text('personality', ko)}',
              reduceMotion: widget.reduceMotion,
            ),
            child: Text(t.shareImage),
          ),
          FilledButton(
            onPressed: () async {
              final saved = await widget.progress.selectCompanion(s.id);
              if (!mounted || !dialogContext.mounted) return;
              Navigator.pop(dialogContext);
              setState(() {});
              if (!saved) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(t.saveError)));
              }
            },
            child: Text(t.travelTogether),
          ),
        ],
      ),
    );
  }
}
