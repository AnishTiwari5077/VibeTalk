// lib/core/instant_route.dart
//
// A zero-duration PageRoute used for call screen navigation.
//
// When a call notification fires on the lock screen, using MaterialPageRoute
// produces a visible left-to-right slide animation (the "shake"). Replace it
// with InstantRoute so the screen appears immediately with no animation.
//
// Usage:
//   Navigator.of(context).push(InstantRoute(IncomingCallScreen(call: call)));

import 'package:flutter/material.dart';

class InstantRoute<T> extends PageRouteBuilder<T> {
  InstantRoute(Widget page)
      : super(
          pageBuilder: (_, __, ___) => page,
          // Zero duration = instant switch, no visible slide/fade.
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          // Return the child as-is — no animation builder needed.
          transitionsBuilder: (_, __, ___, child) => child,
        );
}
