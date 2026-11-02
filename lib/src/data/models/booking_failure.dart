import '../../utils/failure.dart';

class BookingWriteUncertainFailure extends NetworkFailure {
  const BookingWriteUncertainFailure({super.error})
      : super('bookings.errors.write_uncertain');
}

class BookingConflictFailure extends ServerFailure {
  const BookingConflictFailure({super.error})
      : super('bookings.errors.conflict');
}
