import 'package:flutter/widgets.dart';

import '../main.dart';
import 'random_clear_seed.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await seedOneStarPreview();
  runApp(const BloriqApp(firstRunIntro: false));
}
