import 'package:flutter/widgets.dart';

import '../main.dart';
import 'random_clear_seed.dart';

/// Android에서 별도 앱 ID를 쓰는 전체 캠페인 미리 보기 전용 진입점.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (const bool.fromEnvironment('PREVIEW_SEED_PROGRESS', defaultValue: true)) {
    await seedRandomClearPreview(
      seed: const int.fromEnvironment('PREVIEW_SEED', defaultValue: 20261115),
    );
  }
  runApp(const BloriqApp(firstRunIntro: false));
}
