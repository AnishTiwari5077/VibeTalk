// lib/widgets/voice_message_bubble.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';

import '../theme/app_theme.dart';

class VoiceMessageBubble extends StatefulWidget {
  final String audioUrl;
  final Duration? duration;
  final bool isMe;
  final ThemeData theme;
  final bool isDark;

  const VoiceMessageBubble({
    super.key,
    required this.audioUrl,
    this.duration,
    required this.isMe,
    required this.theme,
    required this.isDark,
  });

  @override
  State<VoiceMessageBubble> createState() => _VoiceMessageBubbleState();
}

class _VoiceMessageBubbleState extends State<VoiceMessageBubble> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  // Store subscriptions so they can be cancelled in dispose()
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  void _initializePlayer() {
    _subscriptions.addAll([
      _audioPlayer.onDurationChanged.listen((duration) {
        if (mounted) setState(() => _duration = duration);
      }),
      _audioPlayer.onPositionChanged.listen((position) {
        if (mounted) setState(() => _position = position);
      }),
      _audioPlayer.onPlayerComplete.listen((_) {
        if (mounted) {
          setState(() {
            _isPlaying = false;
            _position = Duration.zero;
          });
        }
      }),
    ]);
  }

  @override
  void dispose() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _togglePlayback() async {
    if (_isPlaying) {
      await _audioPlayer.pause();
      setState(() => _isPlaying = false);
    } else {
      await _audioPlayer.play(UrlSource(widget.audioUrl));
      setState(() => _isPlaying = true);
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final progress = _duration.inMilliseconds > 0
        ? _position.inMilliseconds / _duration.inMilliseconds
        : 0.0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: widget.isMe
            ? LinearGradient(
                colors: [
                  widget.theme.colorScheme.primary,
                  widget.theme.colorScheme.primary.withValues(alpha: .85),
                ],
              )
            : null,
        color: widget.isMe
            ? null
            : (widget.isDark ? AppTheme.cardDark : Colors.grey.shade100),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: _togglePlayback,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: widget.isMe
                    ? Colors.white.withValues(alpha: .2)
                    : widget.theme.colorScheme.primary.withValues(alpha: .1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: widget.isMe
                    ? Colors.white
                    : widget.theme.colorScheme.primary,
                size: 24,
              ),
            ),
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 30,
                  child: Row(
                    children: List.generate(20, (index) {
                      final height = 8.0 + (index % 3) * 8.0;
                      final isActive = (index / 20) < progress;

                      return Expanded(
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 1),
                          decoration: BoxDecoration(
                            color: widget.isMe
                                ? (isActive
                                      ? Colors.white
                                      : Colors.white.withValues(alpha: .3))
                                : (isActive
                                      ? widget.theme.colorScheme.primary
                                      : (widget.isDark
                                            ? Colors.grey.shade700
                                            : Colors.grey.shade300)),
                            borderRadius: BorderRadius.circular(2),
                          ),
                          alignment: Alignment.center,
                          height: height,
                        ),
                      );
                    }),
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  _isPlaying
                      ? _formatDuration(_position)
                      : _formatDuration(widget.duration ?? _duration),
                  style: TextStyle(
                    color: widget.isMe
                        ? Colors.white.withValues(alpha: .9)
                        : (widget.isDark
                              ? AppTheme.textSecondaryDark
                              : AppTheme.textSecondaryLight),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
