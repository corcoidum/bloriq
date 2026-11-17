import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/game_session.dart';
import '../design/game_theme.dart';
import '../design/keep_all_text.dart';
import '../domain/puzzle.dart';
import '../game/mechanic_legend.dart';
import '../l10n/app_localizations.dart';
import '../progression/progression_rules.dart';

/// 캠페인 판을 바꾸기 전에 사람이 먼저 해 보는 시험용 판 묶음.
/// `tools/design_echo_samples.py`가 만들고 `tools/validate_levels.py`가 검증한다.
/// 모든 판은 잔상을 끄면 최단 수가 2수 이상 달라지거나 풀 수 없다.
const echoSamplesAsset = 'assets/levels/echo_samples_v1.json';
const echoSampleFirstId = 9001;

/// 샘플 판의 1부터 센 번호.
int echoSampleNumber(Level level) => level.id - echoSampleFirstId + 1;

List<Level> parseEchoSamples(String source) => [
  for (final item in jsonDecode(source) as List<dynamic>)
    Level.fromJson(item as Map<String, dynamic>),
];

Future<List<Level>> loadEchoSamples() async =>
    parseEchoSamples(await rootBundle.loadString(echoSamplesAsset));

abstract final class EchoSampleText {
  static const title = ProgressionText('echo 샘플 판', 'Echo sample boards');
  static const detail = ProgressionText(
    '시험용 10판 · echo가 풀이를 바꿔요',
    '10 test boards where the echo changes the route',
  );
  static const intro = ProgressionText(
    '새 기준으로 만든 시험용 판이에요. 기록은 앱을 닫으면 지워져요.',
    'Test boards made with the new rule. Records reset when the app closes.',
  );
  static const basic = ProgressionText('기믹 없음', 'No gimmick');

  static ProgressionText stage(int number) =>
      ProgressionText('샘플 $number', 'Sample $number');
  static ProgressionText best(int moves, int minimum) => ProgressionText(
    '내 기록 $moves수 · 최소 $minimum수',
    'Best $moves · minimum $minimum',
  );
  static ProgressionText minimum(int minimum) =>
      ProgressionText('최소 $minimum수', 'Minimum $minimum');
}

/// 샘플 판 목록. 판을 고르면 [onPlay]로 게임을 연다.
class EchoSamplesScreen extends StatefulWidget {
  const EchoSamplesScreen({
    super.key,
    required this.session,
    required this.onPlay,
  });

  final GameSession session;
  final Future<void> Function(Level level) onPlay;

  @override
  State<EchoSamplesScreen> createState() => _EchoSamplesScreenState();
}

class _EchoSamplesScreenState extends State<EchoSamplesScreen> {
  late final Future<List<Level>> _levels = widget.session.loadEchoSamples();
  bool _opening = false;

  Future<void> _play(Level level) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      await widget.onPlay(level);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final colors = GameTheme.colorsOf(context);
    final lang = t.localeName;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        title: Text(EchoSampleText.title.resolve(lang)),
      ),
      body: SafeArea(
        child: FutureBuilder<List<Level>>(
          future: _levels,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Text(t.loadError));
            }
            final levels = snapshot.data;
            if (levels == null) {
              return const Center(child: CircularProgressIndicator());
            }
            return ListView(
              key: const ValueKey('echo-samples'),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: KeepAllText(
                    EchoSampleText.intro.resolve(lang),
                    style: GameTypography.body.copyWith(
                      color: colors.secondaryText,
                    ),
                  ),
                ),
                for (final level in levels) _tile(level, t, colors),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _tile(Level level, AppLocalizations t, GameColors colors) {
    final lang = t.localeName;
    final best = widget.session.sampleBest[level.id];
    final mechanics = MechanicLegend.itemsFor(PuzzleState.initial(level), t);
    final perfect = best == level.minimumMoves;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: colors.surface.withValues(alpha: .8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: (perfect ? colors.reward : colors.outline).withValues(
              alpha: .6,
            ),
          ),
        ),
        child: InkWell(
          key: ValueKey('echo-sample-${echoSampleNumber(level)}'),
          borderRadius: BorderRadius.circular(16),
          onTap: _opening ? null : () => _play(level),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(
                  best == null
                      ? Icons.play_circle_outline_rounded
                      : perfect
                      ? Icons.stars_rounded
                      : Icons.check_circle_outline_rounded,
                  color: best == null ? colors.echoInk : colors.rewardInk,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${EchoSampleText.stage(echoSampleNumber(level)).resolve(lang)}'
                        ' · ${level.boardWidth}×${level.boardHeight}',
                        style: GameTypography.label.copyWith(
                          fontSize: 17,
                          color: colors.text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        best == null
                            ? EchoSampleText.minimum(level.minimumMoves)
                                  .resolve(lang)
                            : EchoSampleText.best(
                                best,
                                level.minimumMoves,
                              ).resolve(lang),
                        style: GameTypography.body.copyWith(
                          color: colors.secondaryText,
                        ),
                      ),
                    ],
                  ),
                ),
                if (mechanics.isEmpty)
                  Text(
                    EchoSampleText.basic.resolve(lang),
                    style: GameTypography.body.copyWith(
                      fontSize: 13,
                      color: colors.secondaryText,
                    ),
                  )
                else
                  // 아이콘만 보여 준다. 설명은 판 안에서 읽는다.
                  SizedBox(
                    width: 48.0 * mechanics.length,
                    child: MechanicLegend(
                      items: mechanics,
                      compact: true,
                      collapsed: true,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
