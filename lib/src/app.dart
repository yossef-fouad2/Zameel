import 'package:zameel/src/imports/imports.dart';
import 'ui/auth/bloc/session_bloc.dart';

class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  late final SessionRouterRefresh _refresh;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    final session = context.read<SessionBloc>();
    _refresh = SessionRouterRefresh(session);
    _router = createAppRouter(session, refreshListenable: _refresh);
  }

  @override
  void dispose() {
    _router.dispose();
    _refresh.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScreenUtilWrapper(
        child: MaterialApp.router(
          title: 'Zameel',
          debugShowCheckedModeBanner: false,
          theme: buildLightTheme(locale: context.locale),
          darkTheme: buildDarkTheme(locale: context.locale),
          themeMode: ThemeMode.system,
          routerConfig: _router,
          localizationsDelegates: context.localizationDelegates,
          supportedLocales: context.supportedLocales,
          locale: context.locale,
          builder: (context, child) => SessionListenerWrapper(
            child: SkeletonWrapper(child: child ?? const SizedBox.shrink()),
          ),
        ),
      );
}
