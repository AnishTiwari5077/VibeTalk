// lib/providers/call_provider.dart
//
// Riverpod providers for incoming/active WebRTC calls.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibetalk/models/call_model.dart';
import 'package:vibetalk/providers/auth_provider.dart';
import 'package:vibetalk/services/webrtc_service.dart';

/// Watches Firestore for an incoming call addressed to the current user.
/// Emits null when there is no ringing call.
final incomingCallProvider = StreamProvider<CallModel?>((ref) {
  final userAsync = ref.watch(currentUserProvider);
  return userAsync.when(
    data: (user) {
      if (user == null) return const Stream.empty();
      return WebRtcService.watchIncomingCalls(user.uid);
    },
    loading: () => const Stream.empty(),
    error: (_, _) => const Stream.empty(),
  );
});

/// Watches a specific active call document by callId.
final activeCallProvider =
    StreamProvider.family<CallModel?, String>((ref, callId) {
  return WebRtcService.watchCall(callId);
});
