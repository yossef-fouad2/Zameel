import '../../imports/imports.dart';
import '../../data/repositories/auth_repository_impl.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/lifestyle_preferences_repository.dart';
import '../../data/repositories/lifestyle_preferences_repository_impl.dart';
import '../../ui/auth/bloc/auth_bloc.dart';
import '../../ui/auth/bloc/session_bloc.dart';

/// A wrapper to initialize the chosen State Management library.
class StateWrapper extends StatelessWidget {
  final Widget child;
  final AuthRepository? repository;
  final LifestylePreferencesRepository? preferencesRepository;

  const StateWrapper({
    super.key,
    required this.child,
    this.repository,
    this.preferencesRepository,
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
