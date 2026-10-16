import 'package:equatable/equatable.dart';

/// Whether a student smokes or is comfortable sharing with smokers.
enum SmokingPreference {
  nonSmoker,
  smoker,
  noPreference,
  smokeFree,
  occasionally,
  comfortableWithSmoking,
  ;

  static SmokingPreference? fromJson(Object? value) {
    if (value is! String) return null;
    for (final preference in values) {
      if (preference.name == value) return preference;
    }
    return null;
  }
}

/// A student's usual sleep window.
enum SleepSchedule {
  earlyBird,
  average,
  nightOwl,
  ;

  static SleepSchedule? fromJson(Object? value) {
    if (value is! String) return null;
    for (final schedule in values) {
      if (schedule.name == value) return schedule;
    }
    return null;
  }
}

/// The atmosphere a student prefers when studying at home.
enum StudyAtmosphere {
  librarySilence,
  ambient,
  social;

  static StudyAtmosphere? fromJson(Object? value) {
    if (value is! String) return null;
    for (final preference in values) {
      if (preference.name == value) return preference;
    }
    return null;
  }
}

/// A student's preferred approach to dishes and kitchen cleanup.
enum DishPolicy {
  immediate,
  sameDay,
  weekend;

  static DishPolicy? fromJson(Object? value) {
    if (value is! String) return null;
    for (final tolerance in values) {
      if (tolerance.name == value) return tolerance;
    }
    return null;
  }
}

/// How often a student prefers guests or social activity in the home.
enum GuestPreference {
  occasional,
  anytime,
  none,
  ;

  static GuestPreference? fromJson(Object? value) {
    if (value is! String) return null;
    for (final preference in values) {
      if (preference.name == value) return preference;
    }
    return null;
  }
}

/// The room arrangement a student is comfortable with.
enum RoomSharingPreference {
  privateRoom,
  doubleRoom,
  tripleRoom;

  static RoomSharingPreference? fromJson(Object? value) {
    if (value is! String) return null;
    for (final preference in values) {
      if (preference.name == value) return preference;
    }
    return null;
  }
}

/// Backwards-compatible aliases for generic lifestyle terminology.
typedef GuestSocialPreference = GuestPreference;

/// The optional lifestyle answers supplied by a student.
///
/// Every answer is nullable because the quiz is optional and can be saved
/// incrementally. Metadata records whether the student completed or skipped
/// the quiz without requiring any answer to be present.
class LifestylePreferences extends Equatable {
  static const int currentVersion = 1;

  final SmokingPreference? smokingPreference;
  final SleepSchedule? sleepSchedule;
  final StudyAtmosphere? studyAtmosphere;
  final DishPolicy? dishPolicy;
  final GuestPreference? guestPreference;
  final RoomSharingPreference? roomSharingPreference;
  final bool isComplete;
  final bool isSkipped;
  final DateTime? completedAt;
  final DateTime? skippedAt;

  const LifestylePreferences({
    SmokingPreference? smokingPreference,
    this.sleepSchedule,
    this.studyAtmosphere,
    this.dishPolicy,
    GuestPreference? guestPreference,
    this.roomSharingPreference,
    bool? isComplete,
    bool? isSkipped,
    this.completedAt,
    this.skippedAt,
    // These aliases make the metadata vocabulary explicit for callers while
    // keeping one canonical representation in the model and JSON.
    bool? completed,
    bool? skipped,
    SmokingPreference? smoking,
    GuestPreference? guests,
  })  : smokingPreference = smokingPreference ?? smoking,
        isComplete = isComplete ?? completed ?? false,
        isSkipped = isSkipped ?? skipped ?? false,
        guestPreference = guestPreference ?? guests;

  /// Alias for [smokingPreference].
  SmokingPreference? get smoking => smokingPreference;

  /// Alias for [guestPreference].
  GuestPreference? get guests => guestPreference;

  /// Alias for [isComplete].
  bool get completed => isComplete;

  /// Alias for [isSkipped].
  bool get skipped => isSkipped;

  Map<String, dynamic> toJson() => {
        'version': currentVersion,
        'smokingPreference': smokingPreference?.name,
        'sleepSchedule': sleepSchedule?.name,
        'studyAtmosphere': studyAtmosphere?.name,
        'dishPolicy': dishPolicy?.name,
        'guestPreference': guestPreference?.name,
        'roomSharingPreference': roomSharingPreference?.name,
        'isComplete': isComplete,
        'isSkipped': isSkipped,
        'completedAt': completedAt?.toUtc().toIso8601String(),
        'skippedAt': skippedAt?.toUtc().toIso8601String(),
      };

  /// Creates a model from persisted data.
  ///
  /// Unknown enum values are treated as unanswered. This lets a newer app
  /// safely read data written by a future or partially migrated version.
  factory LifestylePreferences.fromJson(Map<String, dynamic> json) {
    return LifestylePreferences(
      smokingPreference: SmokingPreference.fromJson(
        json['smokingPreference'] ?? json['smoking'],
      ),
      sleepSchedule: SleepSchedule.fromJson(json['sleepSchedule']),
      studyAtmosphere: StudyAtmosphere.fromJson(json['studyAtmosphere']),
      dishPolicy: DishPolicy.fromJson(json['dishPolicy']),
      guestPreference: GuestPreference.fromJson(
        json['guestPreference'] ?? json['guests'],
      ),
      roomSharingPreference: RoomSharingPreference.fromJson(
        json['roomSharingPreference'],
      ),
      isComplete: _readBool(json['isComplete'] ?? json['completed']),
      isSkipped: _readBool(json['isSkipped'] ?? json['skipped']),
      completedAt: _readDateTime(json['completedAt']),
      skippedAt: _readDateTime(json['skippedAt']),
    );
  }

  LifestylePreferences copyWith({
    Object? smokingPreference = _unset,
    Object? sleepSchedule = _unset,
    Object? studyAtmosphere = _unset,
    Object? dishPolicy = _unset,
    Object? guestPreference = _unset,
    Object? roomSharingPreference = _unset,
    bool? isComplete,
    bool? isSkipped,
    Object? completedAt = _unset,
    Object? skippedAt = _unset,
  }) {
    return LifestylePreferences(
      smokingPreference: identical(smokingPreference, _unset)
          ? this.smokingPreference
          : smokingPreference as SmokingPreference?,
      sleepSchedule: identical(sleepSchedule, _unset)
          ? this.sleepSchedule
          : sleepSchedule as SleepSchedule?,
      studyAtmosphere: identical(studyAtmosphere, _unset)
          ? this.studyAtmosphere
          : studyAtmosphere as StudyAtmosphere?,
      dishPolicy: identical(dishPolicy, _unset)
          ? this.dishPolicy
          : dishPolicy as DishPolicy?,
      guestPreference: identical(guestPreference, _unset)
          ? this.guestPreference
          : guestPreference as GuestPreference?,
      roomSharingPreference: identical(roomSharingPreference, _unset)
          ? this.roomSharingPreference
          : roomSharingPreference as RoomSharingPreference?,
      isComplete: isComplete ?? this.isComplete,
      isSkipped: isSkipped ?? this.isSkipped,
      completedAt: identical(completedAt, _unset)
          ? this.completedAt
          : completedAt as DateTime?,
      skippedAt: identical(skippedAt, _unset)
          ? this.skippedAt
          : skippedAt as DateTime?,
    );
  }

  @override
  List<Object?> get props => [
        smokingPreference,
        sleepSchedule,
        studyAtmosphere,
        dishPolicy,
        guestPreference,
        roomSharingPreference,
        isComplete,
        isSkipped,
        completedAt,
        skippedAt,
      ];

  static const Object _unset = Object();

  static bool _readBool(Object? value) => value is bool ? value : false;

  static DateTime? _readDateTime(Object? value) {
    if (value is! String) return null;
    return DateTime.tryParse(value)?.toUtc();
  }
}
