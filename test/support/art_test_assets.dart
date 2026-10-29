import 'package:bloriq/art/game_art_assets.dart';
import 'package:flutter_test/flutter_test.dart';

/// 네이티브 PNG 디코딩은 widget test의 가상 시계 밖에서 준비한다.
/// 게임 화면에는 production과 동일한 실제 원화 캐시가 주입된다.
Future<void> prepareMoonlitArt() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await GameArtAssets.shared.loadCore();
  await GameArtAssets.shared.prepareChapter(0);
}
