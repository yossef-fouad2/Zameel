import '../../imports/imports.dart';
import '../../data/models/profile_draft.dart';
import '../../data/repositories/profile_repository.dart';
import '../auth/bloc/session_bloc.dart';
import 'profile_cubit.dart';

class AccountPage extends StatelessWidget {
  const AccountPage({super.key, this.landlordLanding = false});
  final bool landlordLanding;

  @override
  Widget build(BuildContext context) => BlocBuilder<SessionBloc, SessionState>(
        // The session resolves asynchronously (cold start, refresh), so the page
        // must rebuild when the user arrives instead of latching a null user.
        buildWhen: (previous, next) => previous.user?.id != next.user?.id,
        builder: (context, session) {
          final user = session.user;
          if (user == null) {
            return Scaffold(
              appBar:
                  AppTopBar(title: 'profile.title'.tr(), centerTitle: false),
              body: const Center(child: CircularProgressIndicator()),
            );
          }
          return BlocProvider(
            key: ValueKey(user.id),
            create: (_) => ProfileCubit(
                repository: context.read<ProfileRepository>(), user: user)
              ..load(),
            child: _ProfileView(landlordLanding: landlordLanding),
          );
        },
      );
}

class _ProfileView extends StatefulWidget {
  const _ProfileView({required this.landlordLanding});
  final bool landlordLanding;
  @override
  State<_ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<_ProfileView> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name, _phone;
  bool _askingToLeave = false;

  @override
  void initState() {
    super.initState();
    final draft = context.read<ProfileCubit>().state.draft;
    _name = TextEditingController(text: draft.name);
    _phone = TextEditingController(text: draft.phone);
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<bool> _allowLeave() async {
    final cubit = context.read<ProfileCubit>();
    if (cubit.state.isBusy || _askingToLeave) return false;
    if (!cubit.state.isDirty) return true;
    _askingToLeave = true;
    final discard = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: Text('profile.discard_title'.tr()),
              content: Text('profile.discard_body'.tr()),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: Text('profile.keep_editing'.tr())),
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: Text('profile.discard'.tr())),
              ],
            ));
    _askingToLeave = false;
    if (!mounted || discard != true) return false;
    cubit.discard();
    return true;
  }

  Future<void> _refresh() async {
    if (await _allowLeave() && mounted) {
      await context.read<ProfileCubit>().load(discard: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ProfileCubit>();
    final flags = context.select((ProfileCubit bloc) => (
          bloc.state.isLoading,
          bloc.state.hasLoaded,
          bloc.state.isBusy,
          bloc.state.isDirty
        ));
    final (loading, loaded, busy, dirty) = flags;
    return BlocListener<ProfileCubit, ProfileState>(
      listenWhen: (previous, next) =>
          previous.profile != next.profile ||
          (previous.isDirty && !next.isDirty) ||
          previous.savedRevision != next.savedRevision,
      listener: (context, state) {
        if (_name.text != state.draft.name) _name.text = state.draft.name;
        if (_phone.text != state.draft.phone) _phone.text = state.draft.phone;
        if (state.hasLoaded) {
          context.read<SessionBloc>().add(SessionProfileUpdated(state.profile));
        }
      },
      child: PopScope(
        canPop: !dirty && !busy,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop || !await _allowLeave() || !context.mounted) return;
          await WidgetsBinding.instance.endOfFrame;
          if (context.mounted && context.canPop()) context.pop();
        },
        child: Scaffold(
          appBar: AppTopBar(
              title: (widget.landlordLanding
                      ? 'auth_flow.landlord_portal'
                      : 'profile.title')
                  .tr(),
              centerTitle: false),
          bottomNavigationBar: loaded
              ? _SaveBar(onSave: () {
                  if (_form.currentState?.validate() ?? false) {
                    FocusScope.of(context).unfocus();
                    cubit.save();
                  }
                }, onDiscard: () {
                  cubit.discard();
                })
              : null,
          body: SafeArea(
              child: Center(
                  child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(AppSpacing.pagePadding,
                    AppSpacing.sm, AppSpacing.pagePadding, AppSpacing.lg),
                children: [
                  const _ProfileHeader(),
                  SizedBox(height: AppSpacing.lg),
                  if (loading) ...[
                    const LinearProgressIndicator(minHeight: 2),
                    SizedBox(height: AppSpacing.md),
                    Text('profile.loading'.tr(),
                        style: context.textTheme.bodyMedium),
                  ] else if (!loaded) ...[
                    const _ProfileMessage(),
                    AppButton(
                        label: 'auth_flow.retry'.tr(),
                        onPressed: () => cubit.load()),
                  ] else ...[
                    _ProfileMessage(onReload: _refresh),
                    Form(
                        key: _form,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        child: _DetailSection(
                            title: 'profile.details_title'.tr(),
                            subtitle: 'profile.details_body'.tr(),
                            children: [
                              AppTextField(
                                  key: const ValueKey('profile.name'),
                                  controller: _name,
                                  enabled: !busy,
                                  label: 'auth.name'.tr(),
                                  textInputAction: TextInputAction.next,
                                  prefixIcon: const Icon(Icons.person_outline),
                                  onChanged: (value) =>
                                      cubit.changeDetails(name: value),
                                  validator: (value) =>
                                      ProfileDraft.validateName(value ?? '')
                                          ?.tr()),
                              SizedBox(height: AppSpacing.md),
                              AppTextField(
                                  key: const ValueKey('profile.phone'),
                                  controller: _phone,
                                  enabled: !busy,
                                  label: 'profile.phone'.tr(),
                                  hint: 'profile.phone_hint'.tr(),
                                  keyboardType: TextInputType.phone,
                                  textInputAction: TextInputAction.done,
                                  prefixIcon: const Icon(Icons.phone_outlined),
                                  onChanged: (value) =>
                                      cubit.changeDetails(phone: value),
                                  validator: (value) =>
                                      ProfileDraft.validatePhone(value ?? '')
                                          ?.tr()),
                              SizedBox(height: AppSpacing.lg),
                              Text('auth.email'.tr(),
                                  style: context.textTheme.labelLarge),
                              SizedBox(height: AppSpacing.xs),
                              SelectableText(cubit.state.profile.email,
                                  style: context.textTheme.bodyMedium),
                              SizedBox(height: AppSpacing.xs),
                              Text('profile.email_locked'.tr(),
                                  style: context.textTheme.bodySmall?.copyWith(
                                      color: context.colors.onSurfaceVariant)),
                            ])),
                    SizedBox(height: AppSpacing.lg),
                    _DetailSection(
                        title: 'profile.language'.tr(),
                        subtitle: 'profile.language_body'.tr(),
                        children: [
                          BlocSelector<ProfileCubit, ProfileState, String>(
                            selector: (state) => state.draft.language,
                            builder: (context, language) =>
                                SegmentedButton<String>(
                              segments: [
                                ButtonSegment(
                                    value: 'en',
                                    label: Text('auth_flow.english'.tr())),
                                ButtonSegment(
                                    value: 'ar',
                                    label: Text('auth_flow.arabic'.tr()))
                              ],
                              selected: {language},
                              onSelectionChanged: busy
                                  ? null
                                  : (values) => cubit.changeDetails(
                                      language: values.single),
                            ),
                          ),
                        ]),
                    SizedBox(height: AppSpacing.lg),
                    if (cubit.state.profile.role == UserRole.student) ...[
                      AppButton(
                          label: 'student_discovery.edit_quiz'.tr(),
                          variant: ButtonVariant.outline,
                          prefixIcon: const Icon(Icons.tune_rounded),
                          onPressed: busy
                              ? null
                              : () async {
                                  if (await _allowLeave() && context.mounted) {
                                    context.pushNamed('lifestyleQuiz');
                                  }
                                }),
                      SizedBox(height: AppSpacing.sm),
                      Text('auth_flow.preferences_cloud'.tr(),
                          style: context.textTheme.bodySmall?.copyWith(
                              color: context.colors.onSurfaceVariant)),
                    ] else if (widget.landlordLanding) ...[
                      _DetailSection(
                          title: 'auth_flow.landlord_ready'.tr(),
                          subtitle: 'auth_flow.landlord_next'.tr(),
                          children: const []),
                    ],
                  ],
                  SizedBox(height: AppSpacing.lg),
                  BlocSelector<SessionBloc, SessionState, bool>(
                      selector: (state) => state.isSigningOut,
                      builder: (context, signingOut) => AppButton(
                          label: 'auth_flow.sign_out'.tr(),
                          variant: ButtonVariant.ghost,
                          isLoading: signingOut,
                          prefixIcon: const Icon(Icons.logout_rounded),
                          onPressed: busy
                              ? null
                              : () async {
                                  if (await _allowLeave() && context.mounted) {
                                    context
                                        .read<SessionBloc>()
                                        .add(const SessionLogoutRequested());
                                  }
                                })),
                ],
              ),
            ),
          ))),
        ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader();

  Future<void> _choosePhoto(BuildContext context) async {
    final cubit = context.read<ProfileCubit>();
    final canRemove = cubit.state.avatarBytes != null ||
        (cubit.state.profile.avatarPath != null && !cubit.state.removeAvatar);
    final action = await showModalBottomSheet<String>(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .85),
        builder: (context) => SingleChildScrollView(
            padding: AppSpacing.bottomSheetPadding,
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('profile.photo_title'.tr(),
                      style: context.textTheme.titleLarge),
                  SizedBox(height: AppSpacing.sm),
                  Text('profile.photo_body'.tr(),
                      style: context.textTheme.bodyMedium),
                  SizedBox(height: AppSpacing.md),
                  ListTile(
                      leading: const Icon(Icons.photo_library_outlined),
                      title: Text('profile.choose_photo'.tr()),
                      onTap: () => Navigator.pop(context, 'choose')),
                  if (canRemove)
                    ListTile(
                        leading: const Icon(Icons.delete_outline),
                        title: Text('profile.remove_photo'.tr()),
                        onTap: () => Navigator.pop(context, 'remove')),
                ])));
    if (!context.mounted) return;
    if (action == 'choose') await cubit.pickAvatar();
    if (action == 'remove') cubit.removePhoto();
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<ProfileCubit, ProfileState>(
        buildWhen: (previous, next) =>
            previous.profile != next.profile ||
            previous.avatarBytes != next.avatarBytes ||
            previous.avatarUrl != next.avatarUrl ||
            previous.removeAvatar != next.removeAvatar ||
            previous.avatarError != next.avatarError ||
            previous.isBusy != next.isBusy ||
            previous.hasLoaded != next.hasLoaded,
        builder: (context, state) {
          final colors = context.colors;
          final photo = Semantics(
              button: true,
              label: 'profile.change_photo'.tr(),
              child: Tooltip(
                  message: 'profile.change_photo'.tr(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: state.isBusy || !state.hasLoaded
                        ? null
                        : () => _choosePhoto(context),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: colors.onPrimaryContainer
                                  .withValues(alpha: .25))),
                      child: Stack(alignment: Alignment.center, children: [
                        ExcludeSemantics(
                            child: ProfileAvatar(
                                name: state.profile.name ?? '',
                                imageUrl:
                                    state.removeAvatar ? null : state.avatarUrl,
                                cacheKey: state.profile.avatarPath,
                                previewBytes: state.avatarBytes)),
                        if (state.isPicking)
                          const SizedBox.square(
                              dimension: 36,
                              child: CircularProgressIndicator(strokeWidth: 2)),
                      ]),
                    ),
                  )));
          final details =
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('profile.eyebrow'.tr(),
                style: context.textTheme.labelSmall
                    ?.copyWith(color: colors.onPrimaryContainer)),
            SizedBox(height: AppSpacing.xs),
            Text(
                (state.profile.name?.trim().isNotEmpty ?? false)
                    ? state.profile.name!
                    : 'profile.title'.tr(),
                style: context.textTheme.headlineSmall?.copyWith(
                    color: colors.onPrimaryContainer,
                    fontWeight: FontWeight.w700)),
            SizedBox(height: AppSpacing.sm),
            KinshipPill(
                label: (state.profile.role == UserRole.landlord
                        ? 'auth.role_landlord'
                        : 'auth.role_student')
                    .tr(),
                icon: Icons.lock_outline,
                backgroundColor: colors.secondaryContainer,
                foregroundColor: colors.onSecondaryContainer),
            TextButton(
                onPressed: state.isBusy || !state.hasLoaded
                    ? null
                    : () => _choosePhoto(context),
                style: TextButton.styleFrom(
                    foregroundColor: colors.onPrimaryContainer),
                child: Text('profile.change_photo'.tr())),
          ]);
          return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                    padding: EdgeInsets.all(AppSpacing.lg),
                    decoration: BoxDecoration(
                        color: colors.primaryContainer,
                        borderRadius: AppBorders.dialog),
                    child: LayoutBuilder(
                        builder: (context, constraints) => constraints
                                        .maxWidth <
                                    340 ||
                                MediaQuery.textScalerOf(context).scale(16) > 24
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                    photo,
                                    SizedBox(height: AppSpacing.md),
                                    details
                                  ])
                            : Row(children: [
                                photo,
                                SizedBox(width: AppSpacing.lg),
                                Expanded(child: details)
                              ]))),
                if (state.avatarError)
                  TextButton.icon(
                      onPressed: state.isBusy
                          ? null
                          : () => context.read<ProfileCubit>().retryAvatar(),
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text('profile.photo_retry'.tr())),
              ]);
        },
      );
}

class _DetailSection extends StatelessWidget {
  const _DetailSection(
      {required this.title, required this.subtitle, required this.children});
  final String title, subtitle;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => AppCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(title,
            style: context.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700)),
        SizedBox(height: AppSpacing.xs),
        Text(subtitle,
            style: context.textTheme.bodySmall
                ?.copyWith(color: context.colors.onSurfaceVariant)),
        if (children.isNotEmpty) SizedBox(height: AppSpacing.lg),
        ...children,
      ]));
}

class _ProfileMessage extends StatelessWidget {
  const _ProfileMessage({this.onReload});
  final VoidCallback? onReload;
  @override
  Widget build(BuildContext context) =>
      BlocSelector<ProfileCubit, ProfileState, String?>(
        selector: (state) => state.errorMessage,
        builder: (context, error) => error == null
            ? const SizedBox.shrink()
            : Padding(
                padding: EdgeInsets.only(bottom: AppSpacing.md),
                child: Semantics(
                    liveRegion: true,
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(error.tr(),
                              style: context.textTheme.bodyMedium
                                  ?.copyWith(color: context.colors.error)),
                          if (error == 'profile.conflict')
                            TextButton(
                                onPressed: onReload,
                                child: Text('profile.reload'.tr())),
                        ])),
              ),
      );
}

class _SaveBar extends StatelessWidget {
  const _SaveBar({required this.onSave, required this.onDiscard});
  final VoidCallback onSave, onDiscard;
  @override
  Widget build(BuildContext context) =>
      BlocSelector<ProfileCubit, ProfileState, (bool, bool, bool, bool)>(
        selector: (state) =>
            (state.canSave, state.isDirty, state.isSaving, state.isPicking),
        builder: (context, flags) {
          final (canSave, dirty, saving, picking) = flags;
          final label = saving
              ? 'profile.saving'
              : picking
                  ? 'profile.preparing_photo'
                  : dirty
                      ? 'profile.unsaved'
                      : 'profile.up_to_date';
          return Material(
              color: context.colors.surface,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: AppSpacing.pagePadding,
                      vertical: AppSpacing.sm),
                  child: Center(
                      heightFactor: 1,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 608),
                        child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              AnimatedSwitcher(
                                  duration:
                                      MediaQuery.disableAnimationsOf(context)
                                          ? Duration.zero
                                          : AppDurations.fast,
                                  child: Text(label.tr(),
                                      key: ValueKey(label),
                                      textAlign: TextAlign.center,
                                      style: context.textTheme.bodySmall
                                          ?.copyWith(
                                              color: context
                                                  .colors.onSurfaceVariant))),
                              SizedBox(height: AppSpacing.xs),
                              Row(children: [
                                Expanded(
                                    child: AppButton(
                                        label: 'profile.save'.tr(),
                                        isLoading: saving,
                                        onPressed: canSave ? onSave : null,
                                        isFullWidth: true)),
                                if (dirty) ...[
                                  SizedBox(width: AppSpacing.sm),
                                  IconButton(
                                      tooltip: 'profile.discard'.tr(),
                                      onPressed:
                                          saving || picking ? null : onDiscard,
                                      icon: const Icon(Icons.undo_rounded))
                                ],
                              ]),
                            ]),
                      )),
                ),
              ));
        },
      );
}
