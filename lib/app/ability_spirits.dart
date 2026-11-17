import 'package:flutter/material.dart';

import '../constellation/constellation_state.dart';
import '../design/game_theme.dart';
import '../design/keep_all_text.dart';
import '../l10n/app_localizations.dart';
import '../progression/progression_rules.dart';
import '../story/story_catalog.dart';
import 'game_session.dart';

/// 능력을 가진 정령 한 명. 세계 1 각 장의 수호 정령이 그 장의 권능을 맡는다.
class AbilitySpirit {
  const AbilitySpirit(this.power, this.spirit);
  final PowerDefinition power;
  final SpiritDefinition spirit;
}

/// 함께 다니는 정령은 이 다섯뿐이다. 능력이 없는 정령은 화면에 내지 않는다.
List<AbilitySpirit> abilitySpirits(StoryCatalog story) => [
  for (final power in powerCatalog)
    if (story
            .inChapter(power.chapter)
            .where((spirit) => spirit.guardian)
            .firstOrNull
        case final spirit?)
      AbilitySpirit(power, spirit),
];

abstract final class AbilitySpiritText {
  static const tab = ProgressionText('정령', 'Spirits');
  static const intro = ProgressionText(
    '별자리를 완성하면 정령이 능력을 들고 합류해요.',
    'Complete a constellation and its spirit joins you with an ability.',
  );
  static ProgressionText joinedNow(String spirit, String power) =>
      ProgressionText('$spirit 합류 · $power', '$spirit joined · $power');
  static ProgressionText joined(int count, int total) => ProgressionText(
    '함께하는 정령 $count / $total',
    'Spirits with you $count / $total',
  );
}

/// 여정의 정령 탭: 능력 정령 다섯과 합류 조건.
class AbilitySpiritsTab extends StatelessWidget {
  const AbilitySpiritsTab({super.key, required this.session});
  final GameSession session;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final colors = GameTheme.colorsOf(context);
    final lang = t.localeName;
    final spirits = abilitySpirits(session.story);
    final atlas = ConstellationAtlas.derive(session.levels, session.progress);
    final joined = spirits
        .where((entry) => session.progression.hasPower(entry.power.id))
        .length;
    return ListView(
      key: const PageStorageKey('journey-spirits-list'),
      primary: false,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      children: [
        Text(
          AbilitySpiritText.joined(joined, spirits.length).resolve(lang),
          key: const ValueKey('journey-spirits-count'),
          style: GameTypography.reward.copyWith(
            fontSize: 20,
            color: colors.text,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 2, bottom: 10),
          child: KeepAllText(
            AbilitySpiritText.intro.resolve(lang),
            style: GameTypography.body.copyWith(color: colors.secondaryText),
          ),
        ),
        for (final entry in spirits)
          _SpiritCard(
            entry: entry,
            unlocked: session.progression.hasPower(entry.power.id),
            constellation: atlas.chapters
                .where(
                  (chapter) =>
                      chapter.definition.chapter == entry.power.chapter,
                )
                .firstOrNull
                ?.definition
                .name(t),
          ),
      ],
    );
  }
}

class _SpiritCard extends StatelessWidget {
  const _SpiritCard({
    required this.entry,
    required this.unlocked,
    required this.constellation,
  });
  final AbilitySpirit entry;
  final bool unlocked;
  final String? constellation;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final colors = GameTheme.colorsOf(context);
    final lang = t.localeName;
    final power = entry.power;
    final status = !unlocked
        ? t.powerLocked(constellation ?? '')
        : power.activeInWorld1
        ? t.powerActive
        : t.powerWorld2;
    final asset = entry.spirit.asset;
    final portrait = asset == null || asset.isEmpty
        ? Icon(Icons.auto_awesome, size: 36, color: colors.rewardInk)
        : Image.asset(asset, fit: BoxFit.contain);
    return Container(
      key: ValueKey('ability-spirit-${power.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: unlocked
            ? colors.reward.withValues(alpha: .12)
            : colors.background.withValues(alpha: .4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: unlocked
              ? colors.reward.withValues(alpha: .6)
              : colors.outline.withValues(alpha: .3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox.square(
            dimension: 64,
            // 아직 합류하지 않은 정령은 실루엣으로만 보여 준다.
            child: unlocked
                ? portrait
                : ColorFiltered(
                    colorFilter: ColorFilter.mode(
                      colors.outline.withValues(alpha: .8),
                      BlendMode.srcIn,
                    ),
                    child: portrait,
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  unlocked ? entry.spirit.name.inLocale(lang) : '?',
                  style: GameTypography.reward.copyWith(
                    fontSize: 18,
                    color: unlocked ? colors.text : colors.secondaryText,
                  ),
                ),
                Text(
                  power.name.resolve(lang),
                  style: GameTypography.label.copyWith(
                    color: unlocked ? colors.rewardInk : colors.secondaryText,
                  ),
                ),
                const SizedBox(height: 2),
                KeepAllText(
                  power.description.resolve(lang),
                  style: GameTypography.body.copyWith(color: colors.text),
                ),
                KeepAllText(
                  status,
                  style: GameTypography.body.copyWith(
                    fontSize: 13,
                    color: colors.secondaryText,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
