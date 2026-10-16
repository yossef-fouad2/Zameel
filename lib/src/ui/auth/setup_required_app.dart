import '../../imports/imports.dart';

class SetupRequiredApp extends StatelessWidget {
  const SetupRequiredApp({super.key});

  @override
  Widget build(BuildContext context) => ScreenUtilWrapper(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildLightTheme(locale: context.locale),
          darkTheme: buildDarkTheme(locale: context.locale),
          localizationsDelegates: context.localizationDelegates,
          supportedLocales: context.supportedLocales,
          locale: context.locale,
          home: Scaffold(
              body: SafeArea(
                  child: Center(
                      child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.settings_outlined, size: 48),
              const SizedBox(height: 16),
              Text('auth_flow.setup_title'.tr(), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              Text('auth_flow.setup_body'.tr(), textAlign: TextAlign.center),
            ]),
          )))),
        ),
      );
}
