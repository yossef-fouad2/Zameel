import 'package:zameel/src/data/models/lifestyle_preferences.dart';
import 'package:zameel/src/data/models/lifestyle_snapshot.dart';
import 'package:zameel/src/utils/utils.dart';

abstract class LifestylePreferencesRepository {
  FutureEither<LifestyleSnapshot> getPreferences({
    required String userId,
  });

  FutureEither<LifestyleSnapshot> savePreferences({
    required String userId,
    required LifestyleSnapshot original,
    required LifestylePreferences preferences,
  });
}
