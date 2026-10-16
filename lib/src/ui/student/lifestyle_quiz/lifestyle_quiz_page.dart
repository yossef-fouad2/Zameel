import 'package:zameel/src/imports/core_imports.dart';
import 'package:zameel/src/imports/packages_imports.dart';
import 'package:zameel/src/data/models/lifestyle_preferences.dart';
import 'package:zameel/src/data/repositories/lifestyle_preferences_repository.dart';

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

class _LifestyleQuizView extends StatelessWidget {
  const _LifestyleQuizView();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<LifestyleQuizBloc, LifestyleQuizState>(
      listenWhen: (previous, current) {
        final saveFinished = previous.isSaving && !current.isSaving;
        return saveFinished ||
            previous.errorMessage != current.errorMessage &&
                current.errorMessage != null;
      },
      listener: (context, state) {
        if (state.isSaving || state.errorMessage != null) {
          if (state.errorMessage != null) {
            showToast(
              context,
              message: _localizedMessage(state.errorMessage!),
              status: 'error',
            );
          }
          return;
        }
        context.go(AppRoutes.discovery);
      },
      builder: (context, state) {
        if (state.loadStatus.isLoading) {
          return const Scaffold(body: Center(child: AppLoading()));
        }

        return Scaffold(
          appBar: const AppTopBar(
            title: '',
            centerTitle: false,
            titleWidget: KinshipBrandMark(compact: true),
          ),
          body: SafeArea(
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.pagePadding,
                AppSpacing.xs,
                AppSpacing.pagePadding,
                AppSpacing.xl,
              ),
              children: [
                _QuizHeader(
                  answeredCount: _answeredCount(state.preferences),
                  isSaving: state.isSaving,
                ),
                SizedBox(height: AppSpacing.lg),
                _PreviewScore(
                  answeredCount: _answeredCount(state.preferences),
                ),
                SizedBox(height: AppSpacing.lg),
                for (final question in _quizQuestions) ...[
                  _QuizQuestionCard(
                    question: question,
                    preferences: state.preferences,
                    onSelected: (value) =>
                        context.read<LifestyleQuizBloc>().add(
                              LifestylePreferencesChanged(
                                question.setValue(state.preferences, value),
                              ),
                            ),
                  ),
                  SizedBox(height: AppSpacing.md),
                ],
                Container(
                  padding: EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: context.colors.surfaceContainerHigh
                        .withValues(alpha: .5),
                    borderRadius: AppBorders.card,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.lock_open_outlined,
                          color: context.colors.primary, size: 22.sp),
                      SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          'student_quiz.privacy_notice'.tr(),
                          style: context.textTheme.bodySmall?.copyWith(
                            color: context.colors.onSurfaceVariant,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: AppSpacing.lg),
                AppButton(
                  label: 'student_quiz.save'.tr(),
                  onPressed: state.isSaving
                      ? null
                      : () => context
                          .read<LifestyleQuizBloc>()
                          .add(const LifestylePreferencesSaveRequested()),
                  isLoading: state.isSaving,
                  isFullWidth: true,
                  height: ButtonSize.large,
                  suffixIcon: const Icon(Icons.arrow_forward),
                ),
                SizedBox(height: AppSpacing.sm),
                TextButton(
                  onPressed: state.isSaving
                      ? null
                      : () => context
                          .read<LifestyleQuizBloc>()
                          .add(const LifestylePreferencesSkipRequested()),
                  child: Text('student_quiz.skip'.tr()),
                ),
              ],
            ),
          ),
          bottomNavigationBar: const _QuizNavigationBar(),
        );
      },
    );
  }

  static int _answeredCount(LifestylePreferences preferences) {
    return [
      preferences.sleepSchedule,
      preferences.studyAtmosphere,
      preferences.dishPolicy,
      preferences.guestPreference,
      preferences.roomSharingPreference,
    ].whereType<Object>().length;
  }

  static String _localizedMessage(String message) {
    return message.startsWith('student_quiz.') ? message.tr() : message;
  }
}

class _QuizHeader extends StatelessWidget {
  const _QuizHeader({required this.answeredCount, required this.isSaving});

  final int answeredCount;
  final bool isSaving;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            KinshipPill(
              label: 'student_quiz.progress'.tr(),
              icon: Icons.circle,
              backgroundColor: colors.tertiaryContainer,
              foregroundColor: colors.onTertiaryContainer,
            ),
            Row(
              children: [
                Icon(Icons.verified_user_outlined,
                    size: 15.sp, color: context.appColors.success),
                SizedBox(width: AppSpacing.xs),
                Text(
                  'student_quiz.private_transparent'.tr(),
                  style: context.textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
        SizedBox(height: AppSpacing.sm),
        ClipRRect(
          borderRadius: AppBorders.full,
          child: LinearProgressIndicator(
            value: .75,
            minHeight: 6.h,
            backgroundColor: colors.surfaceContainerHigh,
            color: colors.primary,
          ),
        ),
        SizedBox(height: AppSpacing.md),
        Text(
          'student_quiz.title'.tr(),
          style: context.textTheme.headlineMedium?.copyWith(
            color: colors.onSurface,
            fontWeight: FontWeight.w800,
            height: 1.2,
          ),
        ),
        SizedBox(height: AppSpacing.xs),
        Text(
          'student_quiz.subtitle'.tr(),
          style: context.textTheme.bodyMedium?.copyWith(
            color: colors.onSurfaceVariant,
            height: 1.45,
          ),
        ),
        if (isSaving) ...[
          SizedBox(height: AppSpacing.sm),
          Text(
            'student_quiz.saving'.tr(),
            style: context.textTheme.labelSmall?.copyWith(
              color: colors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        Semantics(
          label: 'student_quiz.answered_semantics'
              .tr(args: ['$answeredCount', '5']),
          child: const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _PreviewScore extends StatelessWidget {
  const _PreviewScore({required this.answeredCount});

  final int answeredCount;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: AppBorders.card,
      ),
      child: Row(
        children: [
          Container(
            width: 48.w,
            height: 48.w,
            decoration: BoxDecoration(
              color: context.appColors.successContainer,
              borderRadius: AppBorders.input,
            ),
            child: Icon(Icons.diversity_1,
                color: context.appColors.onSuccessContainer, size: 25.sp),
          ),
          SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        'student_quiz.harmony_score'.tr(),
                        style: context.textTheme.labelLarge?.copyWith(
                          color: colors.onSurface,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    SizedBox(width: AppSpacing.xs),
                    KinshipPill(
                      label: 'student_quiz.live_preview'.tr(),
                      backgroundColor:
                          context.appColors.success.withValues(alpha: .12),
                      foregroundColor: context.appColors.success,
                    ),
                  ],
                ),
                SizedBox(height: AppSpacing.xxs),
                Text(
                  'student_quiz.harmony_body'.tr(),
                  style: context.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: AppSpacing.sm),
          Text(
            '$answeredCount/5',
            style: context.textTheme.titleLarge?.copyWith(
              color: context.appColors.success,
              fontWeight: FontWeight.w800,
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
    required this.preferences,
    required this.onSelected,
  });

  final _QuizQuestion question;
  final LifestylePreferences preferences;
  final ValueChanged<Object> onSelected;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 34.w,
                height: 34.w,
                decoration: BoxDecoration(
                  color: context.colors.surfaceContainer,
                  borderRadius: AppBorders.input,
                ),
                child: Icon(question.icon,
                    size: 19.sp, color: context.colors.primary),
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
                        letterSpacing: .7,
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
              option: option,
              selected: question.getValue(preferences) == option.value,
              onTap: () => onSelected(option.value),
            ),
            if (option != question.options.last)
              SizedBox(height: AppSpacing.sm),
          ],
        ],
      ),
    );
  }
}

class _QuizOptionTile extends StatelessWidget {
  const _QuizOptionTile({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final _QuizOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final foreground = selected ? colors.onPrimary : colors.onSurface;
    final secondary =
        selected ? colors.onPrimaryContainer : colors.onSurfaceVariant;

    return Semantics(
      button: true,
      selected: selected,
      label: option.label.tr(),
      child: InkWell(
        onTap: onTap,
        borderRadius: AppBorders.input,
        child: AnimatedContainer(
          duration: AppDurations.fast,
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
              width: selected ? 1.5 : 1,
            ),
            boxShadow: selected ? AppShadows.subtle : AppShadows.none,
          ),
          child: Row(
            children: [
              Icon(option.icon,
                  size: 21.sp,
                  color: selected ? colors.secondaryContainer : secondary),
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
                size: 21.sp,
                color: selected ? context.appColors.success : colors.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuizNavigationBar extends StatelessWidget {
  const _QuizNavigationBar();

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: 2,
      onDestinationSelected: (index) {
        if (index == 2) return;
        showToast(
          context,
          message: 'student_quiz.navigation_coming_soon'.tr(),
          status: 'info',
        );
      },
      destinations: [
        NavigationDestination(
          icon: const Icon(Icons.explore_outlined),
          selectedIcon: const Icon(Icons.explore),
          label: 'student_discovery.explore'.tr(),
        ),
        NavigationDestination(
          icon: const Icon(Icons.task_alt_outlined),
          selectedIcon: const Icon(Icons.task_alt),
          label: 'student_discovery.requests'.tr(),
        ),
        NavigationDestination(
          icon: const Icon(Icons.psychology_outlined),
          selectedIcon: const Icon(Icons.psychology),
          label: 'student_discovery.match_quiz'.tr(),
        ),
        NavigationDestination(
          icon: const Icon(Icons.real_estate_agent_outlined),
          selectedIcon: const Icon(Icons.real_estate_agent),
          label: 'student_discovery.landlord'.tr(),
        ),
      ],
    );
  }
}

class _QuizQuestion {
  const _QuizQuestion({
    required this.category,
    required this.title,
    required this.prompt,
    required this.icon,
    required this.options,
    required this.getValue,
    required this.setValue,
  });

  final String category;
  final String title;
  final String prompt;
  final IconData icon;
  final List<_QuizOption> options;
  final Object? Function(LifestylePreferences preferences) getValue;
  final LifestylePreferences Function(
    LifestylePreferences preferences,
    Object value,
  ) setValue;
}

class _QuizOption {
  const _QuizOption({
    required this.value,
    required this.label,
    required this.icon,
    this.detail,
  });

  final Object value;
  final String label;
  final String? detail;
  final IconData icon;
}

final List<_QuizQuestion> _quizQuestions = [
  _QuizQuestion(
    category: 'student_quiz.category_1',
    title: 'student_quiz.sleep_title',
    prompt: 'student_quiz.sleep_prompt',
    icon: Icons.bedtime_outlined,
    options: [
      const _QuizOption(
        value: SleepSchedule.earlyBird,
        label: 'student_quiz.sleep_early',
        detail: 'student_quiz.sleep_early_detail',
        icon: Icons.wb_sunny_outlined,
      ),
      const _QuizOption(
        value: SleepSchedule.average,
        label: 'student_quiz.sleep_average',
        detail: 'student_quiz.sleep_average_detail',
        icon: Icons.schedule_outlined,
      ),
      const _QuizOption(
        value: SleepSchedule.nightOwl,
        label: 'student_quiz.sleep_night',
        detail: 'student_quiz.sleep_night_detail',
        icon: Icons.nights_stay_outlined,
      ),
    ],
    getValue: (preferences) => preferences.sleepSchedule,
    setValue: _setSleep,
  ),
  _QuizQuestion(
    category: 'student_quiz.category_2',
    title: 'student_quiz.study_title',
    prompt: 'student_quiz.study_prompt',
    icon: Icons.menu_book_outlined,
    options: [
      const _QuizOption(
        value: StudyAtmosphere.librarySilence,
        label: 'student_quiz.study_silence',
        icon: Icons.volume_off_outlined,
      ),
      const _QuizOption(
        value: StudyAtmosphere.ambient,
        label: 'student_quiz.study_ambient',
        icon: Icons.headphones_outlined,
      ),
      const _QuizOption(
        value: StudyAtmosphere.social,
        label: 'student_quiz.study_social',
        icon: Icons.groups_outlined,
      ),
    ],
    getValue: (preferences) => preferences.studyAtmosphere,
    setValue: _setStudy,
  ),
  _QuizQuestion(
    category: 'student_quiz.category_3',
    title: 'student_quiz.clean_title',
    prompt: 'student_quiz.clean_prompt',
    icon: Icons.cleaning_services_outlined,
    options: [
      const _QuizOption(
        value: DishPolicy.immediate,
        label: 'student_quiz.dishes_immediate',
        icon: Icons.sanitizer_outlined,
      ),
      const _QuizOption(
        value: DishPolicy.sameDay,
        label: 'student_quiz.dishes_same_day',
        icon: Icons.timelapse_outlined,
      ),
      const _QuizOption(
        value: DishPolicy.weekend,
        label: 'student_quiz.dishes_weekend',
        icon: Icons.weekend_outlined,
      ),
    ],
    getValue: (preferences) => preferences.dishPolicy,
    setValue: _setDishes,
  ),
  _QuizQuestion(
    category: 'student_quiz.category_4',
    title: 'student_quiz.guests_title',
    prompt: 'student_quiz.guests_prompt',
    icon: Icons.celebration_outlined,
    options: [
      const _QuizOption(
        value: GuestPreference.occasional,
        label: 'student_quiz.guests_occasional',
        icon: Icons.notifications_active_outlined,
      ),
      const _QuizOption(
        value: GuestPreference.anytime,
        label: 'student_quiz.guests_anytime',
        icon: Icons.meeting_room_outlined,
      ),
      const _QuizOption(
        value: GuestPreference.none,
        label: 'student_quiz.guests_none',
        icon: Icons.do_not_disturb_on_outlined,
      ),
    ],
    getValue: (preferences) => preferences.guestPreference,
    setValue: _setGuests,
  ),
  _QuizQuestion(
    category: 'student_quiz.category_5',
    title: 'student_quiz.room_title',
    prompt: 'student_quiz.room_prompt',
    icon: Icons.meeting_room_outlined,
    options: [
      const _QuizOption(
        value: RoomSharingPreference.privateRoom,
        label: 'student_quiz.room_private',
        icon: Icons.single_bed_outlined,
      ),
      const _QuizOption(
        value: RoomSharingPreference.doubleRoom,
        label: 'student_quiz.room_double',
        icon: Icons.king_bed_outlined,
      ),
      const _QuizOption(
        value: RoomSharingPreference.tripleRoom,
        label: 'student_quiz.room_triple',
        icon: Icons.bed_outlined,
      ),
    ],
    getValue: (preferences) => preferences.roomSharingPreference,
    setValue: _setRoom,
  ),
];

LifestylePreferences _setSleep(
        LifestylePreferences preferences, Object value) =>
    preferences.copyWith(sleepSchedule: value as SleepSchedule);

LifestylePreferences _setStudy(
        LifestylePreferences preferences, Object value) =>
    preferences.copyWith(studyAtmosphere: value as StudyAtmosphere);

LifestylePreferences _setDishes(
        LifestylePreferences preferences, Object value) =>
    preferences.copyWith(dishPolicy: value as DishPolicy);

LifestylePreferences _setGuests(
        LifestylePreferences preferences, Object value) =>
    preferences.copyWith(guestPreference: value as GuestPreference);

LifestylePreferences _setRoom(LifestylePreferences preferences, Object value) =>
    preferences.copyWith(roomSharingPreference: value as RoomSharingPreference);
