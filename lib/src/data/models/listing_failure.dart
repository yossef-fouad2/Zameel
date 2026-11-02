import '../../utils/failure.dart';

class ListingNotFoundFailure extends ServerFailure {
  const ListingNotFoundFailure({super.error})
      : super('listings.errors.not_found');
}

class ListingConflictFailure extends ServerFailure {
  const ListingConflictFailure({super.error})
      : super('listings.errors.conflict');
}

class ListingSaveUncertainFailure extends NetworkFailure {
  const ListingSaveUncertainFailure({super.error})
      : super('listings.errors.save_uncertain');
}
