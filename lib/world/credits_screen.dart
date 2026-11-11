import 'package:flutter/material.dart';

import '../design/game_theme.dart';
import '../design/star_art.dart';
import '../l10n/app_localizations.dart';
import 'ending_art.dart';
import 'saga.dart';

Future<void> showCredits(BuildContext context, Saga? saga) => Navigator.of(
  context,
).push<void>(MaterialPageRoute(builder: (_) => CreditsScreen(saga: saga)));

class CreditsScreen extends StatelessWidget {
  const CreditsScreen({super.key, required this.saga, this.onContinue});

  final Saga? saga;
  final VoidCallback? onContinue;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final colors = GameTheme.colorsOf(context);
    final titleStyle = GameTypography.reward.copyWith(color: colors.rewardInk);
    final labelStyle = GameTypography.label.copyWith(
      color: colors.secondaryText,
    );
    return Scaffold(
      backgroundColor: endingNight,
      appBar: AppBar(
        automaticallyImplyLeading: onContinue == null,
        backgroundColor: endingNight,
        foregroundColor: colors.text,
        title: Text(t.endingCredits, style: GameTypography.label),
      ),
      body: CustomPaint(
        painter: const EndingSky(),
        child: SafeArea(
          top: false,
          child: ListView(
            key: const ValueKey('credits-scroll'),
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
            children: [
              Icon(Icons.auto_awesome_rounded, size: 40, color: colors.reward),
              const SizedBox(height: 8),
              Text(
                saga?.title.inLocale(t.localeName) ?? 'BLORIQ',
                textAlign: TextAlign.center,
                style: titleStyle,
              ),
              const SizedBox(height: 8),
              Text(
                t.endingCreator,
                textAlign: TextAlign.center,
                style: labelStyle,
              ),
              const Text(
                'corcoidum',
                textAlign: TextAlign.center,
                style: GameTypography.label,
              ),
              const SizedBox(height: 16),
              for (final world in saga?.worlds ?? const <SagaWorld>[])
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        world.lighthouse == null
                            ? Icons.star_rounded
                            : Icons.light_rounded,
                        size: 16,
                        color: world.theme?.palette?.accent ?? colors.reward,
                      ),
                      const SizedBox(width: 7),
                      Flexible(
                        child: Text(
                          world.title.inLocale(t.localeName),
                          textAlign: TextAlign.center,
                          style: GameTypography.label,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 14),
              Divider(color: colors.outline.withValues(alpha: .35)),
              const SizedBox(height: 8),
              Text(
                t.endingFonts,
                textAlign: TextAlign.center,
                style: labelStyle,
              ),
              const SizedBox(height: 5),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 4,
                children: [
                  for (final name in StarArt.fontLicenses.keys)
                    Text(name, style: GameTypography.label),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'SIL Open Font License 1.1 (OFL)',
                textAlign: TextAlign.center,
                style: GameTypography.body,
              ),
              Center(
                child: TextButton(
                  onPressed: () => showLicensePage(
                    context: context,
                    applicationName: 'BLORIQ',
                  ),
                  child: Text(t.credits, textAlign: TextAlign.center),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                t.endingThankYou,
                textAlign: TextAlign.center,
                style: titleStyle.copyWith(fontSize: 22),
              ),
              if (onContinue != null) ...[
                const SizedBox(height: 12),
                FilledButton(
                  key: const ValueKey('credits-continue'),
                  onPressed: onContinue,
                  child: Text(t.endingContinue, textAlign: TextAlign.center),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
