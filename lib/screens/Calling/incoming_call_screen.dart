// lib/screens/Calling/incoming_call_screen.dart
//
// Shown to the callee when an incoming call arrives while the app is open.
// Accept → navigates to CallingScreen as callee.
// Reject → calls WebRtcService.rejectCall() and dismisses.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:vibetalk/models/call_model.dart';
import 'package:vibetalk/screens/Calling/calling_screen.dart';
import 'package:vibetalk/services/webrtc_service.dart';
import 'package:vibetalk/theme/app_theme.dart';

class IncomingCallScreen extends StatefulWidget {
  final CallModel call;

  const IncomingCallScreen({super.key, required this.call});

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  StreamSubscription? _callDocSub;

  @override
  void initState() {
    super.initState();

    // Keep the controller in [0, 1] — use a Tween for the actual scale range.
    // DO NOT set lowerBound/upperBound outside [0,1]; CurvedAnimation will
    // assert-fail when it receives a value outside that range.
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    // Auto-dismiss if the caller cancels
    _callDocSub = WebRtcService.watchCall(widget.call.callId).listen((call) {
      if (!mounted) return;
      if (call == null ||
          call.status == 'ended' ||
          call.status == 'rejected') {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _callDocSub?.cancel();
    super.dispose();
  }

  Future<void> _accept() async {
    _callDocSub?.cancel();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => CallingScreen(call: widget.call, isCaller: false),
      ),
    );
  }

  Future<void> _reject() async {
    _callDocSub?.cancel();
    await WebRtcService.instance.rejectCall(widget.call.callId);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final callerName = widget.call.callerName;
    final isVideo = widget.call.isVideo;

    return Scaffold(
      backgroundColor: Colors.transparent,
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

                    // Pulsing avatar
                    ScaleTransition(
                      scale: _pulseAnim,
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
