// lib/widgets/message_bubble.dart

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:vibetalk/core/date_formattor.dart';
import 'package:vibetalk/models/message_model.dart';
import 'package:vibetalk/screens/full_screen_viewer.dart';
import 'package:vibetalk/theme/app_theme.dart';
import 'package:vibetalk/widgets/message_reactions.dart';
import 'package:vibetalk/widgets/video_player_widget.dart';
import 'package:vibetalk/widgets/voice_message_bubble.dart';

class MessageBubble extends StatelessWidget {
  final MessageModel message;
  final bool isMe;
  final ThemeData theme;
  final bool isDark;
  final String currentUserId;
  final Function(String messageId, String emoji) onReaction;
  final Function(MessageModel message) onLongPress;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    required this.theme,
    required this.isDark,
    required this.currentUserId,
    required this.onReaction,
    required this.onLongPress,
  });

  // Helper to check if message is media type (image or video)
  bool get isMediaMessage =>
      message.type == MessageType.image || message.type == MessageType.video;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: () => onLongPress(message),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          // No padding for media messages
          padding: isMediaMessage
              ? EdgeInsets.zero
              : const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          decoration: BoxDecoration(
            // No gradient/color for media messages
            gradient: !isMediaMessage && isMe
                ? LinearGradient(
                    colors: [
                      theme.colorScheme.primary,
                      theme.colorScheme.primary.withValues(alpha: .85),
                    ],
                  )
                : null,
            color: !isMediaMessage && !isMe
                ? (isDark ? AppTheme.cardDark : Colors.grey.shade100)
                : null,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(20),
              topRight: const Radius.circular(20),
              bottomLeft: Radius.circular(isMe ? 20 : 4),
              bottomRight: Radius.circular(isMe ? 4 : 20),
            ),
            // No shadow for media messages
            boxShadow: !isMediaMessage
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isDark ? 0.3 : 0.08,
                      ),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Reply preview - only show for non-media messages
              if (message.replyToContent != null && !isMediaMessage) ...[
                Container(
                  padding: const EdgeInsets.all(8),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: (isMe ? Colors.white : Colors.black).withValues(
                      alpha: 0.1,
                    ),
                    borderRadius: BorderRadius.circular(8),
                    border: Border(
                      left: BorderSide(
                        color: isMe
                            ? Colors.white.withValues(alpha: 0.5)
                            : theme.colorScheme.primary,
                        width: 3,
                      ),
                    ),
                  ),
                  child: Text(
                    message.replyToContent!,
                    style: TextStyle(
                      color: isMe
                          ? Colors.white.withValues(alpha: .8)
                          : (isDark
                                ? AppTheme.textSecondaryDark
                                : AppTheme.textSecondaryLight),
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],

              // Image message with full screen viewer
              if (message.type == MessageType.image && message.mediaUrl != null)
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => FullScreenImageViewer(
                          imageUrl: message.mediaUrl!,
                          heroTag: 'message_${message.messageId}',
                        ),
                      ),
                    );
                  },
                  child: Hero(
                    tag: 'message_${message.messageId}',
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      // Constrain max height so very tall images don't fill
                      // the whole screen, but keep the natural aspect ratio.
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxHeight: 320,
                          minHeight: 80,
                        ),
                        child: CachedNetworkImage(
                          imageUrl: message.mediaUrl!,
                          // FIX: do NOT force square cache dimensions.
                          // memCacheWidth/Height: 800 (equal values) squashed
                          // every image into a 1:1 ratio in the memory cache,
                          // then BoxFit.cover cropped it on screen.
                          // Keeping only maxWidthDiskCache lets the cache scale
                          // proportionally without changing the aspect ratio.
                          maxWidthDiskCache: 1200,
                          // FIX: BoxFit.contain preserves the image's natural
                          // width:height ratio within the ConstrainedBox above.
                          // BoxFit.cover was the direct cause of cropping.
                          fit: BoxFit.contain,
                          width: double.infinity,
                          placeholder: (context, url) => Container(
                            height: 200,
                            color: isDark ? Colors.grey[800] : Colors.grey[300],
                            child: const Center(
                              child: CircularProgressIndicator(),
                            ),
                          ),
                          errorWidget: (context, url, error) => Container(
                            height: 200,
                            color: isDark ? Colors.grey[800] : Colors.grey[300],
                            child: Icon(
                              Icons.error_outline_rounded,
                              size: 48,
                              color: isDark ? Colors.grey[400] : Colors.grey[600],
                            ),
                          ),
                          fadeInDuration: const Duration(milliseconds: 200),
                        ),
                      ),
                    ),
                  ),
                )
              // Video message
              else if (message.type == MessageType.video &&
                  message.mediaUrl != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: VideoPlayerWidget(
                    videoUrl: message.mediaUrl!,
                    isDark: isDark,
                  ),
                )
              // Voice message
              else if (message.type == MessageType.voice &&
                  message.mediaUrl != null)
                VoiceMessageBubble(
                  audioUrl: message.mediaUrl!,
                  duration: message.fileName != null
                      ? Duration(
                          seconds:
                              int.tryParse(
                                message.fileName!.replaceAll('s', ''),
                              ) ??
                              0,
                        )
                      : null,
                  isMe: isMe,
                  theme: theme,
                  isDark: isDark,
                )
              // File message
              else if (message.type == MessageType.file &&
                  message.mediaUrl != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: (isMe ? Colors.white : theme.colorScheme.primary)
                            .withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.insert_drive_file_rounded,
                        color: isMe ? Colors.white : theme.colorScheme.primary,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            message.fileName ?? 'File',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: isMe ? Colors.white : null,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Tap to download',
                            style: TextStyle(
                              color: isMe
                                  ? Colors.white.withValues(alpha: .7)
                                  : (isDark
                                        ? AppTheme.textSecondaryDark
                                        : AppTheme.textSecondaryLight),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                )
              // Text message (default)
              else
                Text(
                  message.content,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: isMe ? Colors.white : null,
                    fontSize: 15,
                    height: 1.4,
                  ),
                ),

              // Reactions
              if (message.reactions != null && message.reactions!.isNotEmpty)
                Padding(
                  // Add padding for media messages
                  padding: EdgeInsets.only(
                    top: 8,
                    left: isMediaMessage ? 12 : 0,
                    right: isMediaMessage ? 12 : 0,
                  ),
                  child: MessageReactions(
                    reactions: message.reactions,
                    currentUserId: currentUserId,
                    onReactionTap: (emoji) =>
                        onReaction(message.messageId, emoji),
                    isMyMessage: isMe,
                  ),
                ),

              SizedBox(height: isMediaMessage ? 4 : 6),

              // Timestamp and read status
              Padding(
                // Add padding for media messages
                padding: EdgeInsets.only(
                  left: isMediaMessage ? 12 : 0,
                  right: isMediaMessage ? 12 : 0,
                  bottom: isMediaMessage ? 8 : 0,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (message.isEdited)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Text(
                          'edited',
                          style: TextStyle(
                            // Different color for media messages
                            color: isMediaMessage
                                ? (isDark ? Colors.white70 : Colors.black54)
                                : isMe
                                ? Colors.white.withValues(alpha: .7)
                                : (isDark
                                      ? AppTheme.textTertiaryDark
                                      : AppTheme.textTertiaryLight),
                            fontSize: 10,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    Text(
                      DateFormatter.formatChatTime(message.timestamp),
                      style: TextStyle(
                        // Different color for media messages
                        color: isMediaMessage
                            ? (isDark ? Colors.white70 : Colors.black54)
                            : isMe
                            ? Colors.white.withValues(alpha: .85)
                            : (isDark
                                  ? AppTheme.textTertiaryDark
                                  : AppTheme.textTertiaryLight),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 4),
                      Icon(
                        message.isRead
                            ? Icons.done_all_rounded
                            : Icons.done_rounded,
                        size: 16,
                        color: isMediaMessage
                            ? (message.isRead
                                  ? Colors.lightBlueAccent
                                  : (isDark ? Colors.white70 : Colors.black54))
                            : (message.isRead
                                  ? Colors.lightBlueAccent
                                  : Colors.white.withValues(alpha: .85)),
                      ),
                    ],
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
