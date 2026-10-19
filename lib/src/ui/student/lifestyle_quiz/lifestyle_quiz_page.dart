import 'package:zameel/src/imports/core_imports.dart';
import 'package:zameel/src/imports/packages_imports.dart';
import 'package:zameel/src/data/models/lifestyle_preferences.dart';
import 'package:zameel/src/data/repositories/lifestyle_preferences_repository.dart';
import 'package:zameel/src/ui/auth/bloc/session_bloc.dart';

import 'lifestyle_quiz_bloc.dart';

class LifestyleQuizPage extends StatelessWidget {
  const LifestyleQuizPage({
    super.key,
    required this.userId,
    required this.repository,
  });

  final String userId;
  final LifestylePreferencesRepository repository;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => LifestyleQuizBloc(
        repository: repository,
        userId: userId,
      ),
      child: const _LifestyleQuizView(),
    );
  }
}

class _LifestyleQuizView extends StatefulWidget {
  const _LifestyleQuizView();

  @override
  State<_LifestyleQuizView> createState() => _LifestyleQuizViewState();
}

class _LifestyleQuizViewState extends State<_LifestyleQuizView> {
  bool _askingToLeave = false;
  bool _allowPop = false;

  Future<bool> _confirmDiscard() async {
    final state = context.read<LifestyleQuizBloc>().state;
    if (state.isSaving || _askingToLeave) return false;
    if (!state.isDirty) return true;
    _askingToLeave = true;
    final discard = await context.showAppDialog<bool>(
      builder: (dialogContext) => AlertDialog(
        title: Text('student_quiz.discard_title'.tr()),
        content: Text('student_quiz.discard_body'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('profile.keep_editing'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text('profile.discard'.tr()),
          ),
        ],
      ),
    );
    _askingToLeave = false;
    return mounted && (discard ?? false);
  }

  Future<void> _reload() async {
    if (await _confirmDiscard() && mounted) {
      context
          .read<LifestyleQuizBloc>()
          .add(const LifestyleQuizStarted(discardChanges: true));
    }
  }

  Future<void> _goBack() async {
    if (_allowPop || !await _confirmDiscard() || !mounted) return;
    setState(() => _allowPop = true);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final router = GoRouter.maybeOf(context);
    if (router != null && router.canPop()) {
      router.pop();
    } else if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final (loadStatus, isSaving, isDirty) = context.select(
      (LifestyleQuizBloc bloc) =>
          (bloc.state.loadStatus, bloc.state.isSaving, bloc.state.isDirty),
    );
    return BlocListener<LifestyleQuizBloc, LifestyleQuizState>(
      listenWhen: (previous, current) =>
          previous.savedCount != current.savedCount,
      listener: (context, state) {
        final session = context.read<SessionBloc>();
        if (session.state.status != SessionStatus.authenticated ||
            session.state.user?.id != state.snapshot?.userId) {
          return;
        }
        session.add(SessionPreferencesUpdated(state.snapshot!));
        if (context.canPop()) {
          context.pop();
        } else {
          context.goNamed('discovery');
        }
      },
      child: PopScope(
        canPop: _allowPop || (!isDirty && !isSaving),
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) _goBack();
        },
        child: Scaffold(
          appBar: AppTopBar(
            title: '',
            onPressed: (GoRouter.maybeOf(context)?.canPop() ??
                    Navigator.of(context).canPop())
                ? _goBack
                : null,
            centerTitle: false,
            titleWidget: const KinshipBrandMark(compact: true),
            actions: [
              IconButton(
                tooltip: 'student_onboarding.profile'.tr(),
                onPressed: isSaving ? null : () => context.pushNamed('account'),
                icon: const Icon(Icons.account_circle_outlined),
              ),
            ],
          ),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: switch (loadStatus) {
                  AppStatus.initial || AppStatus.loading => Center(
                      child: Semantics(
                        label: 'student_quiz.loading'.tr(),
                        child: const AppLoading(),
                      ),
                    ),
                  AppStatus.failure => SingleChildScrollView(
                      child: AppEmptyState(
                        icon: Icons.error_outline,
                        title: 'student_quiz.load_error_title'.tr(),
                        subtitle: '${'student_quiz.load_error_body'.tr()}\n\n'
                            '${_localizedMessage(context.read<LifestyleQuizBloc>().state.errorMessage)}',
                        actionLabel: 'student_quiz.retry'.tr(),
                        onAction: () => context
                            .read<LifestyleQuizBloc>()
                            .add(const LifestyleQuizStarted()),
                      ),
                    ),
                  _ => ListView.builder(
                      key: const PageStorageKey('lifestyle-quiz'),
                      padding: EdgeInsets.fromLTRB(
                        AppSpacing.pagePadding,
                        AppSpacing.xs,
                        AppSpacing.pagePadding,
                        AppSpacing.xl,
                      ),
                      itemCount: _quizQuestions.length + 3,
                      itemBuilder: (context, index) => Padding(
                        padding: EdgeInsets.only(bottom: AppSpacing.md),
                        child: switch (index) {
                          0 => const _QuizHeader(),
                          1 => const _AnswerProgress(),
                          _ when index < _quizQuestions.length + 2 =>
                            _QuizQuestionCard(
                                question: _quizQuestions[index - 2]),
                          _ => _QuizActions(onReload: _reload),
                        },
                      ),
                    ),
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _localizedMessage(String? message) =>
    message != null && message.startsWith('student_quiz.')
        ? message.tr()
        : 'student_quiz.save_error'.tr();

class _QuizActions extends StatelessWidget {
  const _QuizActions({required this.onReload});
  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) {
    final (saving, error, needsReload) = context.select(
      (LifestyleQuizBloc bloc) => (
        bloc.state.isSaving,
        bloc.state.errorMessage,
        bloc.state.needsReload
      ),
    );
    final bloc = context.read<LifestyleQuizBloc>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lock_outline, color: context.colors.primary, size: 22),
              SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text('student_quiz.privacy_notice'.tr(),
                    style: context.textTheme.bodySmall
                        ?.copyWith(color: context.colors.onSurfaceVariant)),
              ),
            ],
          ),
        ),
        SizedBox(height: AppSpacing.md),
        AnimatedSwitcher(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : AppDurations.fast,
          child: error == null
              ? const SizedBox.shrink()
              : Semantics(
                  key: ValueKey(error),
                  liveRegion: true,
                  child: Padding(
                    padding: EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Text(_localizedMessage(error),
                        style: context.textTheme.bodyMedium
                            ?.copyWith(color: context.colors.error)),
                  ),
                ),
        ),
        if (needsReload) ...[
          AppButton(
            label: 'student_quiz.reload'.tr(),
            variant: ButtonVariant.outline,
            onPressed: onReload,
          ),
          SizedBox(height: AppSpacing.sm),
        ],
        AppButton(
          label: 'student_quiz.save'.tr(),
          onPressed: saving || needsReload
              ? null
              : () => bloc.add(const LifestylePreferencesSaveRequested()),
          isLoading: saving,
          isFullWidth: true,
          height: ButtonSize.large,
          suffixIcon: const Icon(Icons.arrow_forward),
        ),
        SizedBox(height: AppSpacing.sm),
        TextButton(
          onPressed: saving || needsReload
              ? null
              : () => bloc.add(const LifestylePreferencesSkipRequested()),
          child: Text('student_quiz.skip'.tr()),
        ),
      ],
    );
  }
}

class _QuizHeader extends StatelessWidget {
  const _QuizHeader();

  @override
  Widget build(BuildContext context) {
    final (answeredCount, isSaving, needsImport, isDirty, revision) =
        context.select(
      (LifestyleQuizBloc bloc) => (
        bloc.state.preferences.answeredCount,
        bloc.state.isSaving,
        bloc.state.needsImport,
        bloc.state.isDirty,
        bloc.state.snapshot?.revision ?? 0,
      ),
    );
    final colors = context.colors;
    final status = needsImport
        ? 'student_quiz.local_draft'
        : isDirty
            ? 'student_quiz.unsaved'
            : revision == 0
                ? 'student_quiz.cloud_ready'
                : 'student_quiz.cloud_saved';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            KinshipPill(
              label: 'student_quiz.progress'.tr(),
              icon: Icons.circle,
              backgroundColor: colors.tertiaryContainer,
              foregroundColor: colors.onTertiaryContainer,
            ),
            KinshipPill(
              label: status.tr(),
              icon: needsImport || isDirty
                  ? Icons.edit_outlined
                  : Icons.cloud_outlined,
            ),
          ],
        ),
        SizedBox(height: AppSpacing.sm),
        ClipRRect(
          borderRadius: AppBorders.full,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: answeredCount / _quizQuestions.length),
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : AppDurations.quick,
            curve: AppCurves.smooth,
            builder: (context, value, _) => LinearProgressIndicator(
              value: value,
              semanticsLabel: 'student_quiz.answered_semantics'
                  .tr(args: ['$answeredCount', '${_quizQuestions.length}']),
              minHeight: 6,
              backgroundColor: colors.surfaceContainerHigh,
              color: colors.primary,
            ),
          ),
        ),
        SizedBox(height: AppSpacing.md),
        Text(
          'student_quiz.title'.tr(),
          style: context.textTheme.headlineMedium?.copyWith(
            color: colors.onSurface,
            fontWeight: FontWeight.w800,
          ),
        ),
        SizedBox(height: AppSpacing.xs),
        Text(
          'student_quiz.subtitle'.tr(),
          style: context.textTheme.bodyMedium?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        if (needsImport) ...[
          SizedBox(height: AppSpacing.sm),
          Text('student_quiz.import_notice'.tr(),
              style: context.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurface, fontWeight: FontWeight.w600)),
        ],
        if (isSaving) ...[
          SizedBox(height: AppSpacing.sm),
          Semantics(
            liveRegion: true,
            child: Text(
              'student_quiz.saving'.tr(),
              style: context.textTheme.labelSmall?.copyWith(
                color: colors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _AnswerProgress extends StatelessWidget {
  const _AnswerProgress();

  @override
  Widget build(BuildContext context) {
    final answeredCount = context.select(
        (LifestyleQuizBloc bloc) => bloc.state.preferences.answeredCount);
    final colors = context.colors;
    return Container(
      padding: EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: AppBorders.card,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: context.appColors.successContainer,
              borderRadius: AppBorders.input,
            ),
            child: Icon(Icons.diversity_1,
                color: context.appColors.onSuccessContainer, size: 25),
          ),
          SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'student_quiz.answers_title'.tr(),
                      style: context.textTheme.labelLarge?.copyWith(
                        color: colors.onSurface,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    KinshipPill(
                      label: 'student_quiz.answered_semantics'.tr(
                        args: ['$answeredCount', '${_quizQuestions.length}'],
                      ),
                      backgroundColor: context.appColors.successContainer,
                      foregroundColor: context.appColors.onSuccessContainer,
                    ),
                  ],
                ),
                SizedBox(height: AppSpacing.xxs),
                Text(
                  'student_quiz.answers_body'.tr(),
                  style: context.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuizQuestionCard extends StatelessWidget {
  const _QuizQuestionCard({
    required this.question,
  });

  final _QuizQuestion question;

  @override
  Widget build(BuildContext context) {
    final (selected, saving) = context.select(
      (LifestyleQuizBloc bloc) =>
          (bloc.state.preferences.answerFor(question.id), bloc.state.isSaving),
    );
    final bloc = context.read<LifestyleQuizBloc>();
    return AppCard(
      padding: EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: context.colors.surfaceContainer,
                  borderRadius: AppBorders.input,
                ),
                child: Icon(question.icon,
                    size: 19, color: context.colors.primary),
              ),
              SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      question.category.tr(),
                      style: context.textTheme.labelSmall?.copyWith(
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      question.title.tr(),
                      style: context.textTheme.titleMedium?.copyWith(
                        color: context.colors.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: AppSpacing.md),
          Text(
            question.prompt.tr(),
            style: context.textTheme.bodyMedium?.copyWith(
              color: context.colors.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: AppSpacing.sm),
          for (final option in question.options) ...[
            _QuizOptionTile(
              key: ValueKey('quiz.${question.id.name}.${option.value.name}'),
              option: option,
              selected: selected == option.value,
              onTap: saving
                  ? null
                  : () => bloc
                      .add(LifestyleAnswerChanged(question.id, option.value)),
            ),
            if (option != question.options.last)
              SizedBox(height: AppSpacing.sm),
          ],
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              onPressed: saving || selected == null
                  ? null
                  : () => bloc.add(LifestyleAnswerChanged(question.id, null)),
              child: Text('student_quiz.clear_answer'.tr()),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuizOptionTile extends StatelessWidget {
  const _QuizOptionTile({
    super.key,
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final _QuizOption option;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final foreground = selected ? colors.onPrimary : colors.onSurface;
    final secondary = selected ? colors.onPrimary : colors.onSurfaceVariant;

    return Semantics(
      button: true,
      checked: selected,
      inMutuallyExclusiveGroup: true,
      enabled: onTap != null,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppBorders.input,
        child: AnimatedContainer(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : AppDurations.fast,
          curve: AppCurves.smooth,
          constraints: BoxConstraints(minHeight: 58.h),
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: selected ? colors.primary : colors.surfaceContainerLow,
            borderRadius: AppBorders.input,
            border: Border.all(
              color: selected ? colors.primary : colors.outlineVariant,
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Icon(option.icon, size: 21, color: secondary),
              SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      option.label.tr(),
                      style: context.textTheme.labelLarge?.copyWith(
                        color: foreground,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (option.detail != null)
                      Text(
                        option.detail!.tr(),
                        style: context.textTheme.bodySmall?.copyWith(
                          color: secondary,
                        ),
                      ),
                  ],
                ),
              ),
              Icon(
                selected ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 21,
                color: selected ? colors.onPrimary : colors.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuizQuestion {
  const _QuizQuestion({
    required this.id,
    required this.category,
    required this.title,
    required this.prompt,
    required this.icon,
    required this.options,
  });

  final LifestyleQuestion id;
  final String category;
  final String title;
  final String prompt;
  final IconData icon;
  final List<_QuizOption> options;
}

class _QuizOption {
  const _QuizOption({
    required this.value,
    required this.label,
    required this.icon,
    this.detail,
  });

  final Enum value;
  final String label;
  final String? detail;
  final IconData icon;
}

const List<_QuizQuestion> _quizQuestions = [
  _QuizQuestion(
    id: LifestyleQuestion.sleep,
    category: 'student_quiz.category_1',
    title: 'student_quiz.sleep_title',
    prompt: 'student_quiz.sleep_prompt',
    icon: Icons.bedtime_outlined,
    options: [
      _QuizOption(
        value: SleepSchedule.earlyBird,
        label: 'student_quiz.sleep_early',
        detail: 'student_quiz.sleep_early_detail',
        icon: Icons.wb_sunny_outlined,
      ),
      _QuizOption(
        value: SleepSchedule.average,
        label: 'student_quiz.sleep_average',
        detail: 'student_quiz.sleep_average_detail',
        icon: Icons.schedule_outlined,
      ),
      _QuizOption(
        value: SleepSchedule.nightOwl,
        label: 'student_quiz.sleep_night',
        detail: 'student_quiz.sleep_night_detail',
        icon: Icons.nights_stay_outlined,
      ),
    ],
  ),
  _QuizQuestion(
    id: LifestyleQuestion.study,
    category: 'student_quiz.category_2',
    title: 'student_quiz.study_title',
    prompt: 'student_quiz.study_prompt',
    icon: Icons.menu_book_outlined,
    options: [
      _QuizOption(
        value: StudyAtmosphere.librarySilence,
        label: 'student_quiz.study_silence',
        icon: Icons.volume_off_outlined,
      ),
      _QuizOption(
        value: StudyAtmosphere.ambient,
        label: 'student_quiz.study_ambient',
        icon: Icons.headphones_outlined,
      ),
      _QuizOption(
        value: StudyAtmosphere.social,
        label: 'student_quiz.study_social',
        icon: Icons.groups_outlined,
      ),
    ],
  ),
  _QuizQuestion(
    id: LifestyleQuestion.dishes,
    category: 'student_quiz.category_3',
    title: 'student_quiz.clean_title',
    prompt: 'student_quiz.clean_prompt',
    icon: Icons.cleaning_services_outlined,
    options: [
      _QuizOption(
        value: DishPolicy.immediate,
        label: 'student_quiz.dishes_immediate',
        icon: Icons.sanitizer_outlined,
      ),
      _QuizOption(
        value: DishPolicy.sameDay,
        label: 'student_quiz.dishes_same_day',
        icon: Icons.timelapse_outlined,
      ),
      _QuizOption(
        value: DishPolicy.weekend,
        label: 'student_quiz.dishes_weekend',
        icon: Icons.weekend_outlined,
      ),
    ],
  ),
  _QuizQuestion(
    id: LifestyleQuestion.guests,
    category: 'student_quiz.category_4',
    title: 'student_quiz.guests_title',
    prompt: 'student_quiz.guests_prompt',
    icon: Icons.celebration_outlined,
    options: [
      _QuizOption(
        value: GuestPreference.occasional,
        label: 'student_quiz.guests_occasional',
        icon: Icons.notifications_active_outlined,
      ),
      _QuizOption(
        value: GuestPreference.anytime,
        label: 'student_quiz.guests_anytime',
        icon: Icons.meeting_room_outlined,
      ),
      _QuizOption(
        value: GuestPreference.none,
        label: 'student_quiz.guests_none',
        icon: Icons.do_not_disturb_on_outlined,
      ),
    ],
  ),
  _QuizQuestion(
    id: LifestyleQuestion.room,
    category: 'student_quiz.category_5',
    title: 'student_quiz.room_title',
    prompt: 'student_quiz.room_prompt',
    icon: Icons.meeting_room_outlined,
    options: [
      _QuizOption(
        value: RoomSharingPreference.privateRoom,
        label: 'student_quiz.room_private',
        icon: Icons.single_bed_outlined,
      ),
      _QuizOption(
        value: RoomSharingPreference.doubleRoom,
        label: 'student_quiz.room_double',
        icon: Icons.king_bed_outlined,
      ),
      _QuizOption(
        value: RoomSharingPreference.tripleRoom,
        label: 'student_quiz.room_triple',
        icon: Icons.bed_outlined,
      ),
    ],
  ),
];
