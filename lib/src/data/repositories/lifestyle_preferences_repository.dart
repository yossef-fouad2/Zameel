import 'package:zameel/src/data/models/lifestyle_preferences.dart';
import 'package:zameel/src/utils/utils.dart';

abstract class LifestylePreferencesRepository {
  FutureEither<LifestylePreferences?> getPreferences({
    required String userId,
  });

  FutureEither<void> savePreferences({
    required String userId,
    required LifestylePreferences preferences,
  });

  FutureEither<void> deletePreferences({required String userId});
}
