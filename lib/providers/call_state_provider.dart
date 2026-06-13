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

// A globally accessible controller that ZegoService can use to update state
class CallStateController extends ValueNotifier<CallState> {
  CallStateController() : super(CallState.idle);

  void updateState(CallState newState) {
    if (value != newState) {
      value = newState;
    }
  }
}

// Global instance to be called directly from static methods (like ZegoService)
final globalCallStateController = CallStateController();
