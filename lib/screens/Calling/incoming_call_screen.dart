// lib/screens/Calling/incoming_call_screen.dart
//
// Shown to the callee when an incoming call arrives while the app is open.
// Accept → navigates to CallingScreen as callee.
// Reject → calls WebRtcService.rejectCall() and dismisses.

import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:vibetalk/models/call_model.dart';
import 'package:vibetalk/screens/Calling/calling_screen.dart';
import 'package:vibetalk/services/webrtc_service.dart';
import 'package:vibetalk/theme/app_theme.dart';

class IncomingCallScreen extends StatefulWidget {
  final CallModel call;
  /// When true (tapped Accept on notification shade), navigates directly
  /// to CallingScreen without waiting for the user to tap Accept again.
  final bool autoAccept;

  const IncomingCallScreen({
    super.key,
    required this.call,
    this.autoAccept = false,
  });

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;
  StreamSubscription? _callDocSub;

  /// Guards against: (1) double-tap on Accept/Decline, (2) _callDocSub
  /// firing and popping CallingScreen while _accept() is mid-navigation.
  bool _isNavigating = false;

  // Looping ringtone — plays until the user accepts, declines, or caller hangs up.
  final AudioPlayer _ringtone = AudioPlayer();

  @override
  void initState() {
    super.initState();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    // Auto-dismiss if the caller cancels or the call is rejected.
    // _isNavigating guard prevents this from popping CallingScreen after
    // _accept() has already pushed it (Bug 1 fix).
    //
    // NOTE: we do NOT check `call == null` here. Firestore fires the first
    // snapshot before the document is loaded (null), which would set
    // _isNavigating=true and pop the screen before the user can tap.
    // endCall() always writes status:'ended' — it never deletes the doc —
    // so null is never a valid "caller hung up" signal in this app.
    _callDocSub = WebRtcService.watchCall(widget.call.callId).listen((call) {
      if (!mounted || _isNavigating) return;
      if (call?.status == 'ended' || call?.status == 'rejected') {
        _isNavigating = true;
        _stopRingtone();
        Navigator.of(context).pop();
      }
    });

    // Start ringtone — content URI plays the device's selected ringtone.
    // Loop so it keeps ringing until accepted or rejected.
    _startRingtone();

    // Auto-accept when triggered from the notification Accept button.
    if (widget.autoAccept) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _accept());
    }
  }

  Future<void> _startRingtone() async {
    try {
      await _ringtone.setReleaseMode(ReleaseMode.loop);
      // Bug 2 fix: content:// URIs are Android-only.
      // On iOS they throw; on Android 13+ they may need permissions.
      // Use a platform check + bundled-asset fallback.
      if (defaultTargetPlatform == TargetPlatform.android) {
        await _ringtone.play(
          DeviceFileSource('content://settings/system/ringtone'),
        );
      } else {
        await _ringtone.play(AssetSource('audio/ringtone.mp3'));
      }
    } catch (e) {
      // Fallback: bundled asset when the system ringtone is unavailable.
      try {
        await _ringtone.play(AssetSource('audio/ringtone.mp3'));
      } catch (_) {}
      if (kDebugMode) debugPrint('⚠️ Ringtone error: $e');
    }
  }

  Future<void> _stopRingtone() async {
    try {
      await _ringtone.stop();
    } catch (_) {}
  }

  @override
  void dispose() {
    _ringtone.dispose();
    _pulseCtrl.dispose();
    _callDocSub?.cancel();
    super.dispose();
  }

  Future<void> _accept() async {
    // Bug 1 + Bug 3 fix: guard against double-tap and against _callDocSub
    // popping CallingScreen after we've already pushed it.
    if (_isNavigating) return;
    _isNavigating = true;
    // Cancel subscription BEFORE any await so it can't fire during the
    // async gap between _stopRingtone() and pushReplacement().
    _callDocSub?.cancel();
    await _stopRingtone();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => CallingScreen(call: widget.call, isCaller: false),
      ),
    );
  }

  Future<void> _reject() async {
    if (_isNavigating) return;
    _isNavigating = true;
    // Cancel FIRST so the listener doesn't try to pop() again when
    // rejectCall() sets status: 'rejected' in Firestore.
    _callDocSub?.cancel();
    await _stopRingtone();
    await WebRtcService.instance.rejectCall(widget.call.callId);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final callerName = widget.call.callerName;
    final isVideo = widget.call.isVideo;

    return Scaffold(
      // Minor fix: solid color matching top gradient stop avoids black flash
      // on route entry with hardware acceleration.
      backgroundColor: const Color(0xFF0f0c29),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0f0c29), Color(0xFF302b63), Color(0xFF24243e)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          // Use Column with Expanded so the content fills the safe area
          // without overflowing on small screens.
          child: Column(
            children: [
              // ── Top / centre section fills all remaining space ────────
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Call type label
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isVideo
                                ? Icons.videocam_rounded
                                : Icons.call_rounded,
                            color: Colors.white70,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            isVideo
                                ? 'Incoming Video Call'
                                : 'Incoming Voice Call',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 40),

                    // Pulsing avatar — RepaintBoundary isolates the expensive
                    // boxShadow rasterization so it only repaints this subtree.
                    ScaleTransition(
                      scale: _pulseAnim,
                      child: RepaintBoundary(
                        child: Container(
                          width: 140,
                          height: 140,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [
                                AppTheme.primaryLight,
                                AppTheme.primaryLight.withValues(alpha: 0.4),
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.primaryLight
                                    .withValues(alpha: 0.5),
                                blurRadius: 40,
                                spreadRadius: 10,
                              ),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              callerName.isNotEmpty
                                  ? callerName[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 60,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),

                    Text(
                      callerName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'VibeTalk',
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 13,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
              ),

              // ── Bottom controls ───────────────────────────────────────
              Padding(
                padding: const EdgeInsets.only(bottom: 56),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _CallActionButton(
                      icon: Icons.call_end_rounded,
                      color: Colors.red,
                      label: 'Decline',
                      onTap: _reject,
                    ),
                    _CallActionButton(
                      icon: isVideo
                          ? Icons.videocam_rounded
                          : Icons.call_rounded,
                      color: Colors.green,
                      label: 'Accept',
                      onTap: _accept,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CallActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  const _CallActionButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.5),
                  blurRadius: 20,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 36),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
