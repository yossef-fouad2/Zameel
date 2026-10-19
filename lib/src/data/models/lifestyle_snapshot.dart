import 'package:equatable/equatable.dart';

import 'lifestyle_preferences.dart';

/// A normalized answer. Keep unedited kinds and intensity when saving the quiz.
class LifestyleAnswer extends Equatable {
  const LifestyleAnswer({
    required this.optionType,
    required this.answerKind,
    required this.value,
    this.intensity,
  });

  final String optionType;
  final String answerKind;
  final String value;
  final int? intensity;

  (String, String) get key => (optionType, answerKind);

  factory LifestyleAnswer.fromJson(Map<String, dynamic> json) {
    final type = json['option_type'];
    final kind = json['answer_kind'];
    final value = json['value'];
    final intensity = json['intensity'];
    final validValue = switch (type) {
      'smoking' => switch (kind) {
          'habit' =>
            const ['nonSmoker', 'smoker', 'occasionally'].contains(value),
          'preference' => const [
              'noPreference',
              'smokeFree',
              'comfortableWithSmoking',
            ].contains(value),
          _ => false,
        },
      'sleep_schedule' => SleepSchedule.fromJson(value) != null,
      'study_atmosphere' => StudyAtmosphere.fromJson(value) != null,
      'dish_policy' => DishPolicy.fromJson(value) != null,
      'guest_preference' => GuestPreference.fromJson(value) != null,
      'room_sharing' => RoomSharingPreference.fromJson(value) != null,
      _ => false,
    };
    if (!validValue ||
        (kind != 'habit' && kind != 'preference') ||
        (intensity != null &&
            (intensity is! int || intensity < 1 || intensity > 5))) {
      throw const FormatException('Unsupported lifestyle answer');
    }
    return LifestyleAnswer(
      optionType: type as String,
      answerKind: kind as String,
      value: value as String,
      intensity: intensity as int?,
    );
  }

  Map<String, Object?> toJson() => {
        'option_type': optionType,
        'answer_kind': answerKind,
        'value': value,
        'intensity': intensity,
      };

  @override
  List<Object?> get props => [optionType, answerKind, value, intensity];
}

/// The revision belongs to the entire questionnaire, not individual answers.
class LifestyleSnapshot extends Equatable {
  LifestyleSnapshot({
    required this.userId,
    this.preferences = const LifestylePreferences(),
    this.revision = 0,
    Iterable<LifestyleAnswer> answers = const [],
    this.isLocalDraft = false,
  }) : answers = List.unmodifiable(answers);

  final String userId;
  final LifestylePreferences preferences;
  final int revision;
  final List<LifestyleAnswer> answers;
  final bool isLocalDraft;

  factory LifestyleSnapshot.fromJson(Map<String, dynamic> json) {
    final userId = json['user_id'];
    final revision = json['revision'];
    final complete = json['is_complete'];
    final skipped = json['is_skipped'];
    final rows = json['answers'];
    if (userId is! String ||
        userId.isEmpty ||
        revision is! int ||
        revision < 0 ||
        complete is! bool ||
        skipped is! bool ||
        (complete && skipped) ||
        rows is! List ||
        rows.length > 12) {
      throw const FormatException('Invalid lifestyle snapshot');
    }
    final answers = rows
        .map((row) =>
            LifestyleAnswer.fromJson(Map<String, dynamic>.from(row as Map)))
        .toList();
    final byKey = {for (final answer in answers) answer.key: answer.value};
    if (byKey.length != answers.length) {
      throw const FormatException('Duplicate lifestyle answers');
    }
    DateTime? timestamp(String key, bool present) {
      final value = json[key];
      final parsed = value is String ? DateTime.tryParse(value)?.toUtc() : null;
      if (present ? parsed == null : value != null) {
        throw const FormatException('Invalid lifestyle timestamp');
      }
      return parsed;
    }

    final smoking = answers.where((answer) => answer.optionType == 'smoking');
    final preferences = LifestylePreferences(
      // The legacy scalar cannot represent both kinds. Retain both rows instead
      // of conflating a person's habit with their preferred living conditions.
      smokingPreference: smoking.length == 1
          ? SmokingPreference.fromJson(smoking.single.value)
          : null,
      sleepSchedule: SleepSchedule.fromJson(byKey[('sleep_schedule', 'habit')]),
      studyAtmosphere:
          StudyAtmosphere.fromJson(byKey[('study_atmosphere', 'preference')]),
      dishPolicy: DishPolicy.fromJson(byKey[('dish_policy', 'preference')]),
      guestPreference:
          GuestPreference.fromJson(byKey[('guest_preference', 'preference')]),
      roomSharingPreference:
          RoomSharingPreference.fromJson(byKey[('room_sharing', 'preference')]),
      isComplete: complete,
      isSkipped: skipped,
      completedAt: timestamp('completed_at', complete),
      skippedAt: timestamp('skipped_at', skipped),
    );
    if (complete && !preferences.hasAllQuizAnswers) {
      throw const FormatException('Incomplete lifestyle snapshot');
    }
    return LifestyleSnapshot(
      userId: userId,
      preferences: preferences,
      revision: revision,
      answers: answers,
    );
  }

  LifestyleSnapshot withLocalDraft(LifestylePreferences draft) =>
      LifestyleSnapshot(
        userId: userId,
        revision: revision,
        answers: answers,
        preferences: draft,
        isLocalDraft: true,
      );

  List<LifestyleAnswer> answersFor(LifestylePreferences draft) {
    final result = {for (final answer in answers) answer.key: answer};
    void setAnswer(String type, String kind, String? value) {
      final key = (type, kind);
      if (value == null) {
        result.remove(key);
      } else {
        result[key] = LifestyleAnswer(
          optionType: type,
          answerKind: kind,
          value: value,
          intensity: result[key]?.intensity,
        );
      }
    }

    setAnswer('sleep_schedule', 'habit', draft.sleepSchedule?.name);
    setAnswer('study_atmosphere', 'preference', draft.studyAtmosphere?.name);
    setAnswer('dish_policy', 'preference', draft.dishPolicy?.name);
    setAnswer('guest_preference', 'preference', draft.guestPreference?.name);
    setAnswer('room_sharing', 'preference', draft.roomSharingPreference?.name);
    String smokingKind(SmokingPreference value) => switch (value) {
          SmokingPreference.nonSmoker ||
          SmokingPreference.smoker ||
          SmokingPreference.occasionally =>
            'habit',
          _ => 'preference',
        };
    final previous = preferences.smokingPreference;
    final next = draft.smokingPreference;
    if (previous != null && previous != next) {
      setAnswer('smoking', smokingKind(previous), null);
    }
    if (next != null) setAnswer('smoking', smokingKind(next), next.name);
    return List.unmodifiable(result.values);
  }

  @override
  List<Object?> get props =>
      [userId, preferences, revision, answers, isLocalDraft];
}
