import '../../services/university_service.dart';
import '../../utils/typedefs.dart';
import '../models/university.dart';
import 'university_repository.dart';

class UniversityRepositoryImpl implements UniversityRepository {
  UniversityRepositoryImpl({UniversityService? service})
      : _service = service ?? UniversityService.instance;

  final UniversityService _service;

  static String keyForUser(String userId) =>
      UniversityService.keyForUser(userId);

  @override
  FutureEither<List<University>> getUniversities() =>
      _service.getUniversities();

  @override
  FutureEither<int?> getLastSelection({required String userId}) =>
      _service.getLastSelection(userId: userId);

  @override
  FutureEither<void> saveLastSelection({
    required String userId,
    required int universityId,
  }) =>
      _service.saveLastSelection(userId: userId, universityId: universityId);
}
