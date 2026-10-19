import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_curves.dart';
import '../theme/app_durations.dart';

/// Light, reusable motion for detail flows. Keep the native iOS back gesture.
Page<void> appTransitionPage(
    {required BuildContext context,
    required LocalKey key,
    required Widget child}) {
  if (MediaQuery.disableAnimationsOf(context)) {
    return NoTransitionPage(key: key, child: child);
  }
  if (Theme.of(context).platform == TargetPlatform.iOS) {
    return MaterialPage(key: key, child: child);
  }
  return CustomTransitionPage<void>(
      key: key,
      child: child,
      transitionDuration: AppDurations.quick,
      reverseTransitionDuration: AppDurations.fast,
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          FadeTransition(
              opacity: animation,
              child: SlideTransition(
                  position: animation.drive(
                      Tween(begin: const Offset(0, .025), end: Offset.zero)
                          .chain(CurveTween(curve: AppCurves.smooth))),
                  child: child)));
}
