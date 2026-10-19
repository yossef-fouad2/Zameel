import 'src/imports/core_imports.dart';
import 'src/imports/packages_imports.dart';
import 'src/app.dart';
import 'src/ui/auth/setup_required_app.dart';

Future<void> main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  await EasyLocalization.ensureInitialized();
  await StorageService.instance.init();
  var configured = false;
  try {
    await dotenv.load(fileName: '.env');
    await AppConfig.init();
    configured = true;
  } catch (error) {
    // Do not print client configuration or keys in initialization errors.
    AppLogger.error(
        'Supabase initialization failed; check local configuration.');
  }
  runApp(
    LocalizationWrapper(
      child: configured
          ? const StateWrapper(child: App())
          : const SetupRequiredApp(),
    ),
  );
  // Never defer the first frame on a network/session check. The app's own
  // SessionGatePage shows loading/error states, so startup cannot get stuck
  // behind the native splash when the initial auth response is slow or missed.
  FlutterNativeSplash.remove();
}
