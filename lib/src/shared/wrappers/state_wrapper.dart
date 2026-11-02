import '../../imports/imports.dart';
import '../../data/repositories/auth_repository_impl.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/booking_repository.dart';
import '../../data/repositories/booking_repository_impl.dart';
import '../../data/repositories/lifestyle_preferences_repository.dart';
import '../../data/repositories/lifestyle_preferences_repository_impl.dart';
import '../../data/repositories/profile_repository.dart';
import '../../data/repositories/profile_repository_impl.dart';
import '../../data/repositories/listing_repository.dart';
import '../../data/repositories/listing_repository_impl.dart';
import '../../data/repositories/university_repository.dart';
import '../../data/repositories/university_repository_impl.dart';
import '../../ui/auth/bloc/auth_bloc.dart';
import '../../ui/auth/bloc/session_bloc.dart';

/// A wrapper to initialize the chosen State Management library.
class StateWrapper extends StatelessWidget {
  final Widget child;
  final AuthRepository? repository;
  final LifestylePreferencesRepository? preferencesRepository;
  final ProfileRepository? profileRepository;
  final ListingRepository? listingRepository;
  final UniversityRepository? universityRepository;
  final BookingRepository? bookingRepository;

  const StateWrapper({
    super.key,
    required this.child,
    this.repository,
    this.preferencesRepository,
    this.profileRepository,
    this.listingRepository,
    this.universityRepository,
    this.bookingRepository,
  });

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<AuthRepository>(
            create: (_) => repository ?? AuthRepositoryImpl()),
        RepositoryProvider<LifestylePreferencesRepository>(
          create: (_) =>
              preferencesRepository ?? LifestylePreferencesRepositoryImpl(),
        ),
        RepositoryProvider<ProfileRepository>(
          create: (_) => profileRepository ?? ProfileRepositoryImpl(),
        ),
        RepositoryProvider<ListingRepository>(
          create: (_) => listingRepository ?? ListingRepositoryImpl(),
        ),
        RepositoryProvider<UniversityRepository>(
          create: (_) => universityRepository ?? UniversityRepositoryImpl(),
        ),
        RepositoryProvider<BookingRepository>(
          create: (_) => bookingRepository ?? BookingRepositoryImpl(),
        ),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<SessionBloc>(
            create: (context) => SessionBloc(
                repository: context.read<AuthRepository>(),
                preferencesRepository:
                    context.read<LifestylePreferencesRepository>()),
          ),
          BlocProvider<AuthBloc>(
            create: (context) =>
                AuthBloc(repository: context.read<AuthRepository>()),
          ),
        ],
        child: child,
      ),
    );
  }
}
