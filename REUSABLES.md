# Zameel Reusable Reference

Category-by-category guide to every reusable building block already in the skeleton.
Consult this before writing new UI, helpers, or services — most things you need already exist.

> Companion docs: **DESIGN.md** (design system), **AGENTS.md** (architecture rules), **SETUP.md** (platform/env).

Current auth/design milestone update: the theme uses fixed Kinship-inspired light/dark palettes and bundled Plus Jakarta Sans / IBM Plex Sans Arabic. `buildLightTheme(locale: context.locale)` and `buildDarkTheme(locale: context.locale)` choose typography; there is no seed/primaryColorHex override. See DESIGN.md for the current sizing and accessibility rules.

---

## 0. The import rule (start here)

Every screen/widget imports exactly the two barrels:

```dart
import 'package:zameel/src/imports/core_imports.dart';     // Flutter + easy_localization + whole project
import 'package:zameel/src/imports/packages_imports.dart'; // screenutil, hooks, bloc, go_router, hugeicons, ...
```

- `core_imports.dart` re-exports `shared.dart` → which re-exports **theme tokens, extensions, utils, widgets, enums, wrappers, hooks, assets**, plus routing and `services.dart`.
- `packages_imports.dart` gives you `flutter_screenutil`, `flutter_hooks`, `flutter_bloc`, `go_router`, `fpdart`, `hugeicons`, `flutter_svg`, `skeletonizer`, `flutter_animate`, `cached_network_image`, etc.
- `imports.dart` re-exports both if you prefer one line.
- **Services not in `services.dart`** (media, permission, url_launcher, copy, device_info, version_update) need a direct import.

---

## 1. Theme & design tokens

Read these from `context` — never build a local `ThemeData` or hardcode hex.

### Context extensions — `lib/src/extensions/context_extension.dart`

| Member | Returns | Use |
|--------|---------|-----|
| `context.theme` | `ThemeData` | Full theme |
| `context.colors` | `ColorScheme` | **Primary color access** (`primary`, `onSurface`, `surface`, `error`, `onSurfaceVariant`, `outline`, `outlineVariant`, `secondaryContainer`, …) |
| `context.textTheme` / `context.typography` | `TextTheme` | All text styles (`headlineMedium`, `bodyMedium`, `labelSmall`, …) |
| `context.appColors` | `AppColorsExtension` | Semantic `success`, `warning`, `info` + `on*` and `*Container` variants |
| `context.statusColors` | `ZameelStatusColors` | Marketplace availability/booking/no-data fill, text and border pairs |
| `context.designTokens` | `AppDesignTokens` | Padding/radius/elevation fallback tokens |
| `context.isDarkMode` | `bool` | Brightness branch (use sparingly) |
| `context.width` / `context.height` / `context.screenSize` | `double` / `Size` | Screen size |
| `context.safeArea` | `EdgeInsets` | MediaQuery padding |
| `context.isKeyboardVisible` / `context.hideKeyboard()` | | Keyboard helpers |
| `context.isIOS` / `context.isAndroid` | `bool` | Platform checks |
| `context.currentRoute` | `String` | Current router location |

```dart
final cs = context.colors;
final tt = context.textTheme;
Text('Hi', style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant));
Icon(Icons.check, color: context.appColors.success);
```

### Token classes — `lib/src/theme/theme_constants.dart` (already exported via `shared.dart`)

| Class | Members |
|-------|---------|
| `AppSpacing` | `xxs xs sm ms md ml lg xl xxl xxxl`, `pagePadding`, `itemGap`, `cardPadding`, `formFieldGap` — **already ScreenUtil-scaled** (`16.r`) |
| `AppBorders` | `xs sm md lg xl full bottomSheet`, `button card input dialog`, `shapeSm shapeMd shapeLg stadium` — const radii |
| `AppShadows` | `none subtle card elevated modal` (List<BoxShadow>) |
| `AppDurations` | `instant veryFast fast quick normal medium slow verySlow shimmer`, `pageTransition widgetTransition microInteraction` |
| `AppCurves` | `standard emphasized decelerate accelerate spring easeOutBack linear smooth`, `pageEnter pageExit popupOpen popupClose microInteraction` |

**Responsive convention**

- Named `AppSpacing` getters (e.g. `md`, `pagePadding`) are already scaled: use them bare. `space2` through `space64` and EdgeInsets presets are unscaled constants. Do not append `.w`/`.h` to an already-scaled getter.
- Raw ScreenUtil units for everything else: `.w` (width), `.h` (height), `.r` (radius), `.sp` (font/icon).
- `ScreenUtilInit` is applied once in `app.dart` (`ScreenUtilWrapper`, design size `360×690`) — never add another.
- Avoid `const` widgets whose children depend on `.w/.sp/.r`.

```dart
Padding(padding: EdgeInsets.all(AppSpacing.pagePadding))
SizedBox(height: AppSpacing.lg)
Container(decoration: BoxDecoration(
  color: context.colors.surfaceContainerLow,
  borderRadius: AppBorders.card,
  boxShadow: AppShadows.card,
))
AnimatedContainer(duration: AppDurations.normal, curve: AppCurves.standard)
Icon(Icons.star, size: 20.sp, color: context.colors.primary)
```

---

## 2. Other extensions — `lib/src/extensions/`

### `WidgetExtension` (on any `Widget`)
Chainable wrappers: `paddingAll(v)`, `paddingSymmetric(horizontal:, vertical:)`, `paddingOnly(left:, top:, right:, bottom:)`, `opacity(v)`, `visible(bool, {fallback})`, `.center`, `.expanded`, `.fitted`, `hero(tag)`, `tooltip(msg)`.

```dart
Text('Hi').paddingAll(AppSpacing.md).center
```

### `NumExtension`
`16.kH` (SizedBox height), `16.kW` (SizedBox width), `12.radius` (BorderRadius), `300.ms`, `3.seconds`.

### `StringExtension` / `StringOptionalExtension`
- Validators: `isValidEmail`, `isValidPhoneNumber`, `isValidUrl` (+ aliases `isEmail`, `isPhoneNumber`, `isURL`).
- Format: `capitalizeFirst`, `toTitleCase`, `toK()` (1234 → `1.2k`), `toIntOrNull`, `toDoubleOrNull`, `toColor()`.
- Privacy: `maskEmail`, `maskCenter([visible])`.
- On `String?`: `isNullOrEmpty`, `isNotNullOrEmpty`.

### `DateTimeExtension`
`isToday`, `isYesterday`, `isSameDay(other)`, `toIso8601DateOnly`, `timeAgo()`.

### `IterableExtension` / `ListWidgetExtension`
`firstOrNull`, `lastOrNull`, `mapIndexed((i, e) => …)`, `groupBy(key)`, `chunk(size)`, `.distinct`, `distinctBy(key)`; and for `List<Widget>`: `.separatedBy(separator)`.

---

## 3. Shared widgets — `lib/src/shared/widgets/`

### `AppButton` (`app_button.dart`)
Themed button with variants and sizes.
```dart
AppButton(
  label: 'Save',
  onPressed: _save,
  variant: ButtonVariant.primary, // primary|secondary|outline|ghost|danger|success
  height: ButtonSize.large,       // small(36) | medium(48) | large(56)
  width: ButtonSize.medium,       // optional fixed width
  isLoading: state.isLoading,
  isFullWidth: false,
  prefixIcon: const Icon(Icons.save), // optional
  suffixIcon: null,
  color: null, textColor: null,       // optional overrides
)
```

### `AppCard` (`app_card.dart`)
Surface with optional header row.
```dart
AppCard(
  title: 'Recent', subtitle: 'Last 7 days',
  leading: Icon(Icons.history), trailing: TextButton(onPressed: _all, child: const Text('See all')),
  onTap: _open, showShadow: false,
  padding: null, margin: null, color: null,
  child: Content(),
)
```

### `AppTextField` (`app_text_field.dart`)
Themed `TextFormField` wrapper (styling/labels come from `inputDecorationTheme`).
```dart
AppTextField(
  controller: _c, label: 'Email', hint: 'you@mail.com',
  validator: (v) => AppUtils.isBlank(v) ? 'auth.email_required'.tr() : null,
  keyboardType: TextInputType.emailAddress, textInputAction: TextInputAction.next,
  obscureText: false, enabled: true, readOnly: false,
  prefixIcon: const Icon(Icons.email), suffixIcon: null,
  maxLines: 1, minLines: null, onChanged: null, onFieldSubmitted: null,
  focusNode: null, initialValue: null, autofocus: false,
)
```

### `AppTopBar` (`app_top_bar.dart`) — `implements PreferredSizeWidget`
Back-navigating app bar: shows an accessible directional Back only when a router can pop or a custom back handler is supplied. No cross-role home fallback.
```dart
appBar: AppTopBar(
  title: 'home.title'.tr(),
  titleWidget: null, actions: null,
  centerTitle: true, isTransparent: false, onPressed: null, // custom back handler
)
```

### `AppIcon` (`app_icon.dart`)
Wraps `Icon` with optional size/color; accepts `HugeIcons` data.
```dart
AppIcon(icon: HugeIcons.strokeRoundedHome01, size: 24.sp, color: context.colors.primary)
```

### `AppDivider` / `AppVerticalDivider` (`app_divider.dart`)
```dart
const AppDivider();
const AppDivider.thick();               // 2pt
AppDivider(indent: AppSpacing.md);
const AppVerticalDivider();
```
Params: `height/thickness/indent/endIndent/color` (vertical: `width`).

### `AppLoading` (`app_loading.dart`)
```dart
const AppLoading();                     // inline spinner
AppLoading(message: 'auth.loading'.tr(), size: 28, strokeWidth: 3)
```

### `AppEmptyState` (`app_empty_state.dart`)
```dart
AppEmptyState(
  icon: HugeIcons.strokeRoundedInbox,   // default
  title: 'inbox.empty'.tr(),
  subtitle: 'inbox.empty_body'.tr(),    // optional
  actionLabel: 'common.refresh'.tr(), onAction: _refresh, // both required together
)
```

### `AppErrorWidget` (`app_error_widget.dart`)
```dart
AppErrorWidget(
  title: 'Something went wrong',        // default
  message: error.toString(),
  icon: HugeIcons.strokeRoundedAlertCircle, // default
  onRetry: _load,                       // adds "Try Again" outline button
)
```

### `AppCachedImage` (`app_cached_image.dart`) — network images
```dart
AppCachedImage(
  imageUrl: url,
  width: 200, height: 200,       // raw; scaled internally with .w/.h
  fit: BoxFit.cover, alignment: Alignment.center,
  placeholder: null, errorWidget: null,
  color: null, colorBlendMode: null,
  borderRadius: AppBorders.card,
  fadeInDuration: const Duration(milliseconds: 500),
  useSkeleton: true, cacheKey: null,
)
```

### `CommonImage` (`common_image.dart`) — auto-detects source
```dart
CommonImage(imageUrl: 'https://...' , width: 120, height: 120, fit: BoxFit.cover)
CommonImage(imageUrl: 'assets/icons/x.svg')
CommonImage(imageUrl: 'assets/images/y.png')
```
Routes `http*` → `AppCachedImage`, `*.svg` → `SvgPicture.asset`, else `Image.asset`.

### Toast widgets (`widgets/toast/`)
Low-level toast engine — prefer the `showToast`/`showGlobalToast` helpers (section 4) instead of using these directly.
- `ToastBar({position, builder, toastDuration, animationDuration, autoDismiss, animationCurve})` + `.show(context)` / `ToastBar.removeAll()`.
- `ToastPosition { top, bottom }`
- `ToastCard({title, subtitle, leading, trailing, color, shadowColor, onTap})`

---

## 4. Overlay & feedback helpers

### Snackbars — via `context` (needs a local `BuildContext`)
```dart
context.showSnackBar('Message');
context.showSuccessSnackBar('Saved');
context.showErrorSnackBar('Failed');
context.showTypedSnackBar('Heads up', type: SnackBarType.success); // info|success|warning|error
```

### Toasts — `lib/src/shared/helpers/show_toast.dart`
Floating animated toast (top position, stacking). Two entry points:
```dart
showToast(context, message: 'Saved', status: 'success'); // success|error|warning|info
showGlobalToast(message: 'Saved', status: 'success');    // uses rootContext (no BuildContext needed)
```
Params: `message` (required), `status` (default `'success'`), `icon`, `duration`, `autoDismiss`.

### Dialogs
Two flavours — pick by whether you have a `BuildContext`:
```dart
// Local context: standard Material dialog
context.showAppDialog(builder: (ctx) => AlertDialog(content: Text('Hi')));

// Global (uses rootContext) + backdrop blur + scale transition
showAppDialog(child: AlertDialog(content: Text('Hi')),
  hasBlur: true, blurSigma: 5, barrierColor: Colors.black26, dismissible: true);
showCustomDialogue(child: ...); // alias
```

### Bottom sheets
```dart
// Local context
context.showAppBottomSheet(builder: (ctx) => SheetBody(),
  isScrollControlled: true, useSafeArea: true);

// Global (rootContext) + backdrop blur, M3 top radius
showAppSheet(child: SheetBody(), hasBlur: true, enableDrag: true,
  isScrollControlled: true, useSafeArea: true);
```

---

## 5. Enums — `lib/src/shared/enums/`

| Enum | Values | Notes |
|------|--------|-------|
| `ButtonVariant` | `primary secondary outline ghost danger success` | `AppButton.variant` |
| `ButtonSize` | `small medium large` | `AppButton.height` / `.width` |
| `ButtonState` | `idle loading disabled success error` | generic button state |
| `SnackBarType` | `info success warning error` | `context.showTypedSnackBar` |
| `AppStatus` | `initial loading success failure` | async state — prefer over booleans. Extension: `isInitial isLoading isSuccess isFailure isDone` |

```dart
switch (status) {
  AppStatus.initial => const SizedBox.shrink(),
  AppStatus.loading => const AppLoading(),
  AppStatus.success => Content(),
  AppStatus.failure => AppErrorWidget(onRetry: _load),
}
```

---

## 6. Hooks — `lib/src/shared/hooks/` (flutter_hooks)

### `useTimer`
```dart
final tick = useTimer(
  duration: const Duration(minutes: 5),
  onComplete: _onDone,
  isActive: true, tick: const Duration(seconds: 1), autoStart: true,
);
Text(tick.remainingMmSs); // "4:59" / "1:02:03"
```
Also exported: `formatMmSs(Duration)`.

### `usePermission`
```dart
final (status, isLoading, request) = usePermission(Permission.camera);
```

### `useLaunchUrl`
```dart
final (isLoading, launch) = useLaunchUrl();
await launch('https://example.com'); // handles URL/phone formatting + error toast
```

### `useCopy`
```dart
final (copyToClipboard, hasCopied) = useCopy();
await copyToClipboard('text'); // shows success toast automatically
```

---

## 7. Services — `lib/src/services/`

Convention: singletons via `ClassName.instance`, async methods return `FutureEither<T>` (from `runTask`), no `BuildContext` params.

### Exported by `services.dart` (available via `core_imports.dart`)

**`AuthService.instance`** (`auth_service.dart`) — Supabase auth.
```dart
Stream<AuthSessionChange> get authStateChanges;
FutureEither<void> login({required String email, required String password});
FutureEither<SignUpOutcome> signUp({required String name, required String email,
    required String password, required UserRole role});
FutureEither<void> confirmEmail({required String email, required String code});
FutureEither<void> resendConfirmation({required String email});
FutureEither<void> forgotPassword({required String email});
FutureEither<void> verifyRecovery({required String email, required String code});
FutureEither<void> updatePassword({required String password});
FutureEither<void> logout();
FutureEither<AppUser?> getCurrentUser();
```
`getCurrentUser` loads the current user's protected `profiles` row. Role/name are never authorized from user-editable metadata. `SignUpOutcome.confirmationRequired` is not an authenticated session. Use `AuthRepository` from blocs, `AuthFeedback` for UI feedback, and central router guards for access. No `BuildContext` is passed into auth events/services. See SETUP.md for OTP email templates and SQL prerequisites.

**`StorageService.instance`** (`storage_service.dart`) — SharedPreferences. Call `await StorageService.instance.init()` once.
Setters return `FutureEither<bool>`: `setString/setBool/setInt/setDouble/setStringList`.
Getters (sync): `getString/getBool/getInt/getDouble/getStringList`. Plus `containsKey`, `remove(key)`, `clear()`.

**`SecureStorageService.instance`** (`secure_storage_service.dart`) — Keychain/Keystore.
`write(key, value)`, `read(key)`, `delete(key)`, `deleteAll()`, `containsKey(key)` — all `FutureEither`.

**`InternetConnectionService()`** (regular constructor, `internet_connection_service.dart`)
`Future<bool> hasConnection()`.

**`PathService.instance`** (`path_service.dart`)
`getDocumentsDirectory()`, `getTempDirectory()`, `getAppSupportDirectory()`, `getAppLibraryDirectory()`, `getExternalStorageDirectoryPath()` — each `FutureEither<Directory>`.

### Direct-import services (not in the barrel)

**`MediaService.instance`** (`media_service.dart`)
`pickImage({required ImageSource source, maxWidth, maxHeight, imageQuality})`,
`pickMultiImage({...})`, `pickVideo({required ImageSource source, maxDuration})` — each `FutureEither<File?>` / `<List<File>>`. Handles permissions.

**`PermissionService.instance`** (`permission_service.dart`)
`checkStatus(permission)`, `request(permission)`, `requestMultiple(list)`, `openSettings()`.

**`UrlLauncherService.instance`** (`url_launcher_service.dart`)
`launch(url, {mode})` — auto-formats web/phone URLs.

**`CopyService.instance`** (`copy_service.dart`)
`copy(text)`.

**`DeviceInfoService.instance`** (`device_info_service.dart`)
`getFullDeviceInfo()` → `FutureEither<Map<String,dynamic>>` (platform-specific keys).

**`VersionUpdateService.instance`** (`version_update_service.dart`)
`checkForUpdate({appleId, playStoreId})`, `checkAndShowUpdate({..., mandatory})`, `showUpdateAlert(...)`, `showUpdateBottomSheet(...)`, `showUpdatePage(...)`.

### Supabase client
`AppConfig.supabase` (`lib/src/config/app_config.dart`) — the `SupabaseClient`. All DB calls go through repositories/services, never widgets.

---

## 8. Utils — `lib/src/utils/`

| Thing | File | Usage |
|-------|------|-------|
| `AppLogger` | `logger.dart` | `AppLogger.info/success/warning/error(msg[, err, stack])` (debug-only). Globals: `logInfo`, `logSuccess`, `logWarning`, `logError`. |
| `runTask<T>()` | `task_runner.dart` | Wraps an async action → `FutureEither<T>`; maps exceptions to `Failure`, optional `requiresNetwork: true` guard. |
| `Failure` types | `failure.dart` | `ServerFailure`, `CacheFailure`, `NetworkFailure`, `UnknownFailure` (each `message`, optional `error`). |
| Typedefs | `typedefs.dart` | `FutureEither<T>`, `FutureEitherVoid`, `StreamEither<T>`. |
| `AppErrorHandler` | `error_handler.dart` | `AppErrorHandler.format(error)` → user-safe string. |
| `AppUtils` | `app_utils.dart` | `isNull`, `isBlank`, `capitalizeFirst`, `isPhoneNumber`, `isValidEmail`, `isURL`, `hasMatch`. |
| `Debouncer` / `Throttler` | `debouncer.dart` | `Debouncer(delay).run(fn)` / `Throttler(delay).run(fn)`; `dispose()`. |
| `FormCardFormatter` | `input_formatters.dart` | `TextInputFormatter` that groups digits in 4s (card numbers). |
| `PlatformInfo` | `platform_info.dart` | `isWeb isAndroid isIOS isMacOS isWindows isLinux isMobile isDesktop`. |

`formatNumber(num)` in `lib/src/shared/helpers/format_number.dart` → `1,000,000` (comma grouping).

---

## 9. Wrappers — `lib/src/shared/wrappers/`

Applied once in `main.dart` / `app.dart`; don't re-add.
- `LocalizationWrapper` — `EasyLocalization` (locales `en`, `ar`, path `assets/translations`).
- `StateWrapper` — provides `SessionBloc` + `AuthBloc` via `MultiBlocProvider`.
- `ScreenUtilWrapper({designSize})` — `ScreenUtilInit` (default `360×690`).
- `SessionListenerWrapper` removes native splash and displays session-operation failures. `createAppRouter` and `sessionRedirect` own routing/guards; the router is created/disposed with `App`.
- `SkeletonWrapper` — skeleton loading; useful locally too:
```dart
SkeletonWrapper(isLoading: state.isLoading, child: Content())
```
Params: `enabled`, `isLoading`, `effect`, `containersColor`, `textBoneBorderRadius`, `ignorePointers`, …

---

## 10. Assets & routing

### `AppAssets` — `lib/src/shared/app_assets.dart`
```dart
AppAssets.googleIcon;    // assets/icons/google.svg
AppAssets.facebookIcon;
AppAssets.appleIcon;
```

### Routing — `lib/src/routing/`
- `AppRoutes` (`app_routes.dart`): `splash home onboarding login signup forgotPassword`. Never hardcode path strings.
- `createAppRouter` (`app_router.dart`): creates the app-owned `GoRouter` with session/role/recovery guards. Register new routes here (declare in `AppRoutes` too).
- `rootNavigatorKey` / `rootContext` (`global_navigator.dart`): context-free navigation/overlays for services.

```dart
context.go(AppRoutes.home);   // replace stack
context.push(AppRoutes.signup); // push on top
```

---

## 11. New-page recipe (ties it together)

```dart
import 'package:zameel/src/imports/core_imports.dart';
import 'package:zameel/src/imports/packages_imports.dart';

class ProfilePage extends HookWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final tt = context.textTheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppTopBar(title: 'profile.title'.tr()),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.pagePadding), // already scaled
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppCard(
                title: 'profile.section'.tr(),
                child: Text('profile.body'.tr(),
                    style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
              ),
              SizedBox(height: AppSpacing.lg),
              AppButton(
                label: 'common.save'.tr(),
                isFullWidth: true,
                onPressed: () => showGlobalToast(message: 'common.saved'.tr()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

Then: add route constant in `AppRoutes` → register in `appRouter` → add keys to `assets/translations/*.json` → run the localization generate command (SETUP.md).

---

## 12. Cheat-sheet (do / don't)

**Do**
- `context.colors` / `context.appColors` / `context.textTheme`
- `AppSpacing` / `AppBorders` / `AppShadows` / `AppDurations` / `AppCurves` (use `AppSpacing.*` bare)
- `.w/.h/.r/.sp` only for raw values
- `AppButton` / `AppCard` / `AppTextField` / `AppTopBar` for UI consistency
- `showGlobalToast` / `showAppDialog` / `showAppSheet` for overlays
- `.tr()` for every user-visible string
- `runTask` + `Failure` in services; `AppLogger` for logs

**Don't**
- New `ThemeData`, new `ScreenUtilInit`, or a second state/routing library
- Hardcoded hex colors or magic padding/radius numbers
- `const` widgets depending on ScreenUtil values
- Backend/network calls directly from widgets
- `AppSpacing.md.w` (double-scales — `AppSpacing.md` is already scaled)
