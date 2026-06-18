import 'package:flutter/foundation.dart';

enum CallState {
  idle,
  calling,
  ringing,
  connected,
  ended,
  rejected,
  timeout,
}

// A globally accessible controller that WebRtcService can use to update state.
class CallStateController extends ValueNotifier<CallState> {
  CallStateController() : super(CallState.idle);

  void updateState(CallState newState) {
    if (value != newState) {
      value = newState;
    }
  }
}

// Global instance — called directly from WebRtcService and call screens.
final globalCallStateController = CallStateController();
