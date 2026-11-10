import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

class FailingSaveStore extends InMemorySharedPreferencesStore {
  FailingSaveStore._(super.data) : super.withData();

  final rejectedKeys = <String>{};

  static Future<FailingSaveStore> install() async {
    final preferences = await SharedPreferences.getInstance();
    final store = FailingSaveStore._({
      for (final key in preferences.getKeys())
        'flutter.$key': preferences.get(key)!,
    });
    SharedPreferencesStorePlatform.instance = store;
    return store;
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (rejectedKeys.any((rejected) => key == 'flutter.$rejected')) {
      return false;
    }
    return super.setValue(valueType, key, value);
  }
}
