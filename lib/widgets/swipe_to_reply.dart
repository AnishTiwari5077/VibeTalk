// lib/screens/conversation/widgets/swipe_to_reply.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SwipeToReply extends StatefulWidget {
  final Widget child;
  final VoidCallback onReply;
  final bool isMe;

  const SwipeToReply({
    super.key,
    required this.child,
    required this.onReply,
    required this.isMe,
  });

  @override
  State<SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<SwipeToReply> {
  double _dragExtent = 0;
  bool _dragStarted = false;

  static const double _kSwipeThreshold = 80.0;
  static const double _kMaxSwipe = 100.0;

  void _handleDragStart(DragStartDetails details) {
    _dragStarted = true;
    _dragExtent = 0;
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (!_dragStarted) return;

    setState(() {
      final delta = widget.isMe
          ? -details.primaryDelta!
          : details.primaryDelta!;
      _dragExtent = (_dragExtent + delta).clamp(0.0, _kMaxSwipe);
    });
  }

  void _handleDragEnd(DragEndDetails details) {
    if (!_dragStarted) return;
    _dragStarted = false;

    if (_dragExtent >= _kSwipeThreshold) {
      HapticFeedback.mediumImpact();
      widget.onReply();
    }

    setState(() {
      _dragExtent = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = (_dragExtent / _kSwipeThreshold).clamp(0.0, 1.0);

    return GestureDetector(
      onHorizontalDragStart: _handleDragStart,
      onHorizontalDragUpdate: _handleDragUpdate,
      onHorizontalDragEnd: _handleDragEnd,
      child: Stack(
        alignment: widget.isMe ? Alignment.centerRight : Alignment.centerLeft,
        children: [
          if (_dragExtent > 0)
            Positioned(
              right: widget.isMe ? null : 16,
              left: widget.isMe ? 16 : null,
              child: Opacity(
                opacity: progress,
                child: Transform.scale(
                  scale: progress,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: .2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.reply_rounded,
                      color: theme.colorScheme.primary,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ),
          Transform.translate(
            offset: Offset(widget.isMe ? -_dragExtent : _dragExtent, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}
