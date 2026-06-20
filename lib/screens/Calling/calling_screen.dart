// lib/screens/Calling/calling_screen.dart
//
// Active call screen for both caller and callee.
// Renders RTCVideoView for video calls, avatar UI for audio calls.
// Controls: mute, speaker, camera flip, camera toggle, hang-up.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:vibetalk/models/call_model.dart';
import 'package:vibetalk/providers/call_state_provider.dart';
import 'package:vibetalk/services/webrtc_service.dart';
import 'package:vibetalk/theme/app_theme.dart';

class CallingScreen extends StatefulWidget {
  final CallModel call;
  final bool isCaller;

  const CallingScreen({super.key, required this.call, required this.isCaller});

  @override
  State<CallingScreen> createState() => _CallingScreenState();
}

class _CallingScreenState extends State<CallingScreen>
    with WidgetsBindingObserver {
  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();

  StreamSubscription? _localStreamSub;
  StreamSubscription? _remoteStreamSub;
  StreamSubscription? _statusSub;
  StreamSubscription? _callDocSub;

  bool _isMuted = false;
  bool _isSpeakerOn = false;
  bool _isCameraOff = false;
  bool _isFrontCamera = true;
  bool _remoteConnected = false;
  bool _isEnding = false; // guard: prevents double-pop

  String _statusLabel = '';
  int _callDurationSeconds = 0;
  Timer? _durationTimer;
  Timer? _autoEndTimer; // Bug 4 fix: cancellable instead of Future.delayed

  final _webrtc = WebRtcService.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _initCall();
  }

  Future<void> _initCall() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();

    _statusLabel = widget.isCaller ? 'Calling...' : 'Connecting...';
    globalCallStateController.updateState(
      widget.isCaller ? CallState.calling : CallState.ringing,
    );

    // Wire local stream → renderer
    _localStreamSub = _webrtc.localStream.listen((stream) {
      if (!mounted) return;
      setState(() => _localRenderer.srcObject = stream);
    });

    // Wire remote stream → renderer
    _remoteStreamSub = _webrtc.remoteStream.listen((stream) {
      if (!mounted) return;
      setState(() {
        _remoteRenderer.srcObject = stream;
        // Bug 2 fix: only start timer on FIRST non-null emission.
        // Without this guard, timer resets to 0 if WebRTC re-emits
        // the stream during renegotiation / network reconnect.
        if (stream != null && !_remoteConnected) {
          _statusLabel = 'Connected';
          globalCallStateController.updateState(CallState.connected);
          _startTimer();
        }
        _remoteConnected = stream != null;
      });
    });

    // Listen for call status changes (rejected / ended by other side)
    _statusSub = _webrtc.callStatus.listen((status) {
      if (!mounted) return;
      if (status == 'ended' || status == 'rejected') {
        _endCallAndPop(fromRemote: true);
      } else if (status == 'accepted') {
        setState(() {
          _statusLabel = 'Connected';
          globalCallStateController.updateState(CallState.connected);
        });
      }
    });

    // Also watch the Firestore document directly — catches cases where the
    // callee rejects via Firestore but the callStatus stream didn't fire.
    _callDocSub = WebRtcService.watchCall(widget.call.callId).listen((call) {
      if (!mounted || call == null) return;
      if (call.status == 'ended' || call.status == 'rejected') {
        _endCallAndPop(fromRemote: true);
      }
    });

    // Auto-cancel: if nobody answers in 60 seconds, hang up.
    // Bug 4 fix: use a Timer field so it can be cancelled properly
    // and doesn't hold a reference to this for 60 s after dispose.
    if (widget.isCaller) {
      _autoEndTimer = Timer(const Duration(seconds: 60), () {
        if (mounted && !_isEnding && !_remoteConnected) {
          debugPrint('⏰ [CallingScreen] Auto-cancel: no answer after 60s');
          _endCallAndPop();
        }
      });
    }

    try {
      if (widget.isCaller) {
        await _webrtc.createCall(
          callId: widget.call.callId,
          isVideo: widget.call.isVideo,
        );
        // Offer written — callee can now see the call.
        if (mounted) setState(() => _statusLabel = 'Ringing...');
      } else {
        await _webrtc.joinCall(
          callId: widget.call.callId,
          isVideo: widget.call.isVideo,
        );
      }
    } catch (e) {
      debugPrint('❌ [CallingScreen] Call init error: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Call failed: $e')));
        Navigator.of(context).pop();
      }
    }
  }

  void _startTimer() {
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _callDurationSeconds++);
    });
  }

  String get _formattedDuration {
    final m = (_callDurationSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (_callDurationSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _endCallAndPop({bool fromRemote = false}) async {
    // Prevent re-entry: Firestore watcher + status stream can both fire
    // at the same time when the call ends.
    if (_isEnding) return;
    _isEnding = true;

    // Cancel all subscriptions FIRST so null-stream callbacks
    // don't blank the screen while we're still navigating away.
    _durationTimer?.cancel();
    _autoEndTimer?.cancel(); // Bug 4 fix: cancel the auto-end timer
    await _localStreamSub?.cancel();
    await _remoteStreamSub?.cancel();
    await _statusSub?.cancel();
    await _callDocSub?.cancel();
    _localStreamSub = null;
    _remoteStreamSub = null;
    _statusSub = null;
    _callDocSub = null;

    if (!fromRemote) {
      await _webrtc.endCall(widget.call.callId);
    } else {
      // Bug 1 fix: remote already wrote to Firestore (status: ended/rejected).
      // Only clean up local WebRTC resources — do NOT overwrite the status,
      // which would turn 'rejected' into 'ended' and corrupt call history.
      await _webrtc.cleanupLocal();
    }

    globalCallStateController.updateState(CallState.ended);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    _autoEndTimer?.cancel(); // Bug 4 fix
    _localStreamSub?.cancel();
    _remoteStreamSub?.cancel();
    _statusSub?.cancel();
    _callDocSub?.cancel();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  // ─── UI ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Prevent the route from popping without user confirmation.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop)
          return; // already popped (shouldn't happen when canPop=false)
        await _onBackPressed();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // ── Background / Remote video ──────────────────────────────────
            _buildRemoteView(),

            // ── Local preview (picture-in-picture) ────────────────────────
            if (widget.call.isVideo && _localRenderer.srcObject != null)
              _buildLocalPreview(),

            // ── Top bar: name + status ─────────────────────────────────────
            _buildTopBar(),

            // ── Bottom controls ────────────────────────────────────────────
            _buildControls(),
          ],
        ),
      ),
    );
  }

  /// Called when the hardware/gesture back button is pressed.
  /// Shows a quick dialog so the user can choose between going back
  /// (call stays active) or explicitly ending the call.
  Future<void> _onBackPressed() async {
    if (_isEnding) return; // already ending — nothing to intercept

    final shouldEnd = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.call_end_rounded, color: Colors.redAccent, size: 24),
            SizedBox(width: 10),
            Text('End Call?', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: const Text(
          'Do you want to end the call?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(
              'Stay',
              style: TextStyle(color: Colors.white70, fontSize: 15),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('End Call', style: TextStyle(fontSize: 15)),
          ),
        ],
      ),
    );

    if (shouldEnd == true && mounted) {
      _endCallAndPop();
    }
  } // end _onBackPressed

  Widget _buildRemoteView() {
    if (widget.call.isVideo && _remoteConnected) {
      return Positioned.fill(
        child: RTCVideoView(
          _remoteRenderer,
          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
        ),
      );
    }

    // Audio call OR waiting for remote — show gradient + avatar
    final name = widget.isCaller
        ? widget.call.calleeName
        : widget.call.callerName;

    return Positioned.fill(
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF1a2a6c), Color(0xFF0d0d0d)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Avatar circle
              Container(
                width: 130,
                height: 130,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.primaryLight.withValues(alpha: 0.8),
                      AppTheme.primaryLight.withValues(alpha: 0.3),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primaryLight.withValues(alpha: 0.4),
                      blurRadius: 30,
                      spreadRadius: 8,
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 56,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 8),
              // Animated dots when not yet connected
              if (!_remoteConnected)
                _AnimatedStatusDots(label: _statusLabel)
              else
                Text(
                  _formattedDuration,
                  style: const TextStyle(color: Colors.white70, fontSize: 16),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLocalPreview() {
    return Positioned(
      top: 60,
      right: 16,
      width: 100,
      height: 140,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white24, width: 1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: RTCVideoView(
            _localRenderer,
            mirror: _isFrontCamera,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              // Call type chip
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.white12,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      widget.call.isVideo
                          ? Icons.videocam_rounded
                          : Icons.call_rounded,
                      color: Colors.white70,
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'VibeTalk',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              // Duration when connected
              if (_remoteConnected && widget.call.isVideo)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black38,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.fiber_manual_record,
                        color: Colors.red,
                        size: 10,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _formattedDuration,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                        ),
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

  Widget _buildControls() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [Colors.black87, Colors.transparent],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _ControlButton(
                    icon: _isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                    label: _isMuted ? 'Unmute' : 'Mute',
                    active: _isMuted,
                    onTap: () {
                      _webrtc.toggleMute();
                      setState(() => _isMuted = !_isMuted);
                    },
                  ),
                  _ControlButton(
                    icon: _isSpeakerOn
                        ? Icons.volume_up_rounded
                        : Icons.volume_down_rounded,
                    label: _isSpeakerOn ? 'Speaker' : 'Earpiece',
                    active: _isSpeakerOn,
                    onTap: () async {
                      await _webrtc.toggleSpeaker();
                      setState(() => _isSpeakerOn = !_isSpeakerOn);
                    },
                  ),
                  if (widget.call.isVideo) ...[
                    _ControlButton(
                      icon: _isCameraOff
                          ? Icons.videocam_off_rounded
                          : Icons.videocam_rounded,
                      label: _isCameraOff ? 'Cam Off' : 'Cam On',
                      active: _isCameraOff,
                      onTap: () {
                        _webrtc.toggleCamera();
                        setState(() => _isCameraOff = !_isCameraOff);
                      },
                    ),
                    _ControlButton(
                      icon: Icons.flip_camera_ios_rounded,
                      label: 'Flip',
                      onTap: () async {
                        await _webrtc.switchCamera();
                        setState(() => _isFrontCamera = !_isFrontCamera);
                      },
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 24),
              // Hang-up button
              GestureDetector(
                onTap: () => _endCallAndPop(),
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.red,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.red.withValues(alpha: 0.5),
                        blurRadius: 20,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.call_end_rounded,
                    color: Colors.white,
                    size: 36,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Reusable control button ──────────────────────────────────────────────────

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _ControlButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active ? Colors.white : Colors.white24,
              boxShadow: active
                  ? [
                      BoxShadow(
                        color: Colors.white.withValues(alpha: 0.3),
                        blurRadius: 10,
                      ),
                    ]
                  : null,
            ),
            child: Icon(
              icon,
              color: active ? Colors.black87 : Colors.white,
              size: 26,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

// ─── Animated "Calling..." dots ───────────────────────────────────────────────

class _AnimatedStatusDots extends StatefulWidget {
  final String label;
  const _AnimatedStatusDots({required this.label});

  @override
  State<_AnimatedStatusDots> createState() => _AnimatedStatusDotsState();
}

class _AnimatedStatusDotsState extends State<_AnimatedStatusDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, _) {
        final dotCount = (_anim.value * 3).floor() + 1;
        return Text(
          '${widget.label}${'.' * dotCount}',
          style: const TextStyle(color: Colors.white60, fontSize: 16),
        );
      },
    );
  }
}
