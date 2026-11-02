import '../../utils/typedefs.dart';
import '../models/university.dart';

abstract class UniversityRepository {
  FutureEither<List<University>> getUniversities();

  FutureEither<int?> getLastSelection({required String userId});

  FutureEither<void> saveLastSelection({
    required String userId,
    required int universityId,
  });
}
