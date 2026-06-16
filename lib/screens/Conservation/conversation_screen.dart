// lib/screens/conversation/conversation_screen.dart

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibetalk/core/date_formattor.dart';

import 'package:vibetalk/models/message_model.dart';
import 'package:vibetalk/models/user_model.dart';
import 'package:vibetalk/providers/auth_provider.dart';
import 'package:vibetalk/providers/chart_provider.dart';
import 'package:vibetalk/providers/user_provider.dart';
import 'package:vibetalk/screens/Conservation/conversation_controller.dart';
import 'package:vibetalk/services/notification_services.dart';

import 'package:vibetalk/theme/app_theme.dart';
import 'package:vibetalk/widgets/block_user_view.dart';
import 'package:vibetalk/widgets/empty_message_view.dart';
import 'package:vibetalk/widgets/message_bubble.dart';
import 'package:vibetalk/widgets/message_option_sheet.dart';
import 'package:vibetalk/widgets/reply_preview.dart';
import 'package:vibetalk/widgets/swipe_to_reply.dart';
import 'package:vibetalk/widgets/typing_indicator.dart';
import 'package:vibetalk/widgets/user_avatar.dart';
import 'package:vibetalk/widgets/voice_recorder_button.dart';

class ConversationScreen extends ConsumerStatefulWidget {
  final String chatId;
  final UserModel friend;

  const ConversationScreen({
    super.key,
    required this.chatId,
    required this.friend,
  });

  @override
  ConsumerState<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends ConsumerState<ConversationScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  bool _isSending = false;
  bool _isUploadingMedia = false; // true only during file/voice uploads

  late final ConversationController _controller;
  late final _userRepository = ref.read(userRepositoryProvider);
  String? _currentUserId;

  Timer? _typingTimer;
  Timer? _typingDebounceTimer; // debounces the first typing Firestore write
  bool _isCurrentlyTyping = false;

  MessageModel? _replyToMessage;
  String? _replyToSenderName;

  @override
  void initState() {
    super.initState();
    _controller = ConversationController(
      ref: ref,
      context: context,
      chatId: widget.chatId,
      friend: widget.friend,
    );

    _currentUserId = ref.read(currentUserProvider).value?.uid;

    // Suppress foreground FCM notifications while viewing this chat
    NotificationService.setActiveChatId(widget.chatId);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller.markMessagesAsRead();
      // ⭐ FIX: Tell system you're viewing this chat
      if (_currentUserId != null) {
        _userRepository.updateTypingStatus(
          userId: _currentUserId!,
          isTyping: false,
          chatId: widget.chatId, // ⭐ Set chatId to track which chat you're in
        );
      }
    });

    _messageController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _messageController.removeListener(_onTextChanged);
    _messageController.dispose();
    _scrollController.dispose();
    _typingTimer?.cancel();
    _typingDebounceTimer?.cancel();

    // Re-enable foreground notifications when leaving the chat
    NotificationService.clearActiveChatId();

    // ⭐ FIX: Always clear chatId when leaving (not just when typing)
    if (_currentUserId != null) {
      _userRepository.updateTypingStatus(
        userId: _currentUserId!,
        isTyping: false,
        chatId: null, // ⭐ Clear chatId when leaving
      );
    }

    super.dispose();
  }

  void _onTextChanged() {
    if (_messageController.text.isNotEmpty && !_isCurrentlyTyping) {
      // Debounce: only fire the Firestore write after 300ms of continuous typing.
      // This prevents rapid delete/retype from spamming Firestore.
      _typingDebounceTimer?.cancel();
      _typingDebounceTimer = Timer(const Duration(milliseconds: 300), _startTyping);
    } else if (_messageController.text.isEmpty && _isCurrentlyTyping) {
      _typingDebounceTimer?.cancel();
      _stopTyping();
    }

    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 2), _stopTyping);
  }

  void _startTyping() {
    if (_currentUserId == null) return;
    _isCurrentlyTyping = true;
    _controller.updateTypingStatus(userId: _currentUserId!, isTyping: true);
  }

  void _stopTyping() {
    if (_currentUserId == null || !_isCurrentlyTyping) return;
    _isCurrentlyTyping = false;
    _controller.updateTypingStatus(userId: _currentUserId!, isTyping: false);
  }

  void _setReplyMessage(MessageModel message, String senderName) {
    setState(() {
      _replyToMessage = message;
      _replyToSenderName = senderName;
    });
    FocusScope.of(context).requestFocus(FocusNode());
  }

  void _cancelReply() {
    setState(() {
      _replyToMessage = null;
      _replyToSenderName = null;
    });
  }

  Future<void> _sendTextMessage() async {
    if (_messageController.text.trim().isEmpty || _isSending) return;

    final content = _messageController.text.trim();
    _messageController.clear();
    _stopTyping();

    setState(() => _isSending = true);

    try {
      await _controller.sendTextMessage(
        content: content,
        replyToMessageId: _replyToMessage?.messageId,
        replyToContent: _replyToMessage?.content,
        replyToSenderId: _replyToMessage?.senderId,
      );
      _cancelReply();
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _showMessageOptions(MessageModel message) async {
    final currentUser = ref.read(currentUserProvider).value;
    final isMyMessage = message.senderId == currentUser?.uid;

    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => MessageOptionsSheet(
        message: message,
        isMyMessage: isMyMessage,
        onReactionSelected: (emoji) {
          Navigator.pop(context);
          _controller.addReaction(message.messageId, emoji);
        },
        onReply: () {
          Navigator.pop(context);
          _setReplyMessage(
            message,
            isMyMessage ? 'You' : widget.friend.username,
          );
        },
        onEdit: isMyMessage
            ? () {
                Navigator.pop(context);
                _editMessage(message);
              }
            : null,
        onDelete: isMyMessage
            ? () {
                Navigator.pop(context);
                _controller.deleteMessage(message.messageId);
              }
            : null,
        onCopy: () {
          Navigator.pop(context);
          _controller.copyToClipboard(message.content);
        },
      ),
    );
  }

  Future<void> _editMessage(MessageModel message) async {
    if (!mounted) return;

    final controller = TextEditingController(text: message.content);

    final newContent = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Message'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Enter new message',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    controller.dispose();

    if (newContent != null &&
        newContent.isNotEmpty &&
        newContent != message.content) {
      await _controller.editMessage(message.messageId, newContent);
    }
  }

  Future<void> _sendVoiceMessage(String audioPath, Duration duration) async {
    setState(() {
      _isSending = true;
      _isUploadingMedia = true;
    });

    try {
      await _controller.sendVoiceMessage(audioPath, duration);
    } catch (e) {
      debugPrint('Error sending voice message: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send voice message: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
          _isUploadingMedia = false;
        });
      }
    }
  }

  Future<void> _sendMediaMessage(MessageType type, File file) async {
    setState(() {
      _isSending = true;
      _isUploadingMedia = true;
    });

    try {
      debugPrint('Sending ${type.name} message from conversation screen');
      await _controller.sendMediaMessage(type, file);
      debugPrint(
        '${type.name} message sent successfully from conversation screen',
      );
    } catch (e) {
      debugPrint('Error in _sendMediaMessage: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.toString().contains('too large')
                  ? 'File is too large. Maximum size is 50 MB'
                  : 'Failed to send ${type.name}',
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
          _isUploadingMedia = false;
        });
      }
    }
  }

  Future<void> _showAttachmentOptions() async {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: isDark ? AppTheme.cardDark : AppTheme.cardLight,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Send Attachment',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 20),
                        _buildAttachmentOption(
                          icon: Icons.camera_alt_rounded,
                          label: 'Camera',
                          color: Colors.purple,
                          onTap: () async {
                            Navigator.pop(context);
                            try {
                              final image = await _controller.capturePhoto();
                              if (image != null) {
                                await _sendMediaMessage(
                                  MessageType.image,
                                  image,
                                );
                              }
                            } catch (e) {
                              debugPrint('Camera error: $e');
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Failed to capture photo: $e',
                                    ),
                                  ),
                                );
                              }
                            }
                          },
                          theme: theme,
                          isDark: isDark,
                        ),
                        const SizedBox(height: 12),
                        _buildAttachmentOption(
                          icon: Icons.image_rounded,
                          label: 'Photo',
                          color: Colors.blue,
                          onTap: () async {
                            Navigator.pop(context);
                            try {
                              final image = await _controller
                                  .pickImageFromGallery();
                              if (image != null) {
                                await _sendMediaMessage(
                                  MessageType.image,
                                  image,
                                );
                              }
                            } catch (e) {
                              debugPrint('Photo picker error: $e');
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Failed to select photo: $e'),
                                  ),
                                );
                              }
                            }
                          },
                          theme: theme,
                          isDark: isDark,
                        ),
                        const SizedBox(height: 12),
                        _buildAttachmentOption(
                          icon: Icons.videocam_rounded,
                          label: 'Video',
                          color: Colors.red,
                          onTap: () async {
                            Navigator.pop(context);
                            try {
                              debugPrint('Opening video picker...');
                              final video = await _controller
                                  .pickVideoFromGallery();

                              if (video != null) {
                                debugPrint('Video selected, sending...');
                                await _sendMediaMessage(
                                  MessageType.video,
                                  video,
                                );
                              } else {
                                debugPrint('No video selected');
                              }
                            } catch (e) {
                              debugPrint('Video error in UI: $e');
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      e.toString().contains('too large')
                                          ? 'Video is too large. Maximum size is 50 MB'
                                          : 'Failed to send video: $e',
                                    ),
                                    duration: const Duration(seconds: 3),
                                  ),
                                );
                              }
                            }
                          },
                          theme: theme,
                          isDark: isDark,
                        ),
                        const SizedBox(height: 12),
                        _buildAttachmentOption(
                          icon: Icons.insert_drive_file_rounded,
                          label: 'Document',
                          color: Colors.orange,
                          onTap: () async {
                            Navigator.pop(context);
                            try {
                              final file = await _controller.pickDocument();
                              if (file != null) {
                                await _sendMediaMessage(MessageType.file, file);
                              }
                            } catch (e) {
                              debugPrint('Document picker error: $e');
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Failed to select document: $e',
                                    ),
                                  ),
                                );
                              }
                            }
                          },
                          theme: theme,
                          isDark: isDark,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAttachmentOption({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    required ThemeData theme,
    required bool isDark,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark
                ? color.withValues(alpha: .1)
                : color.withValues(alpha: .05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: .3), width: 1),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: .3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(icon, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showBlockOptions() async {
    final currentUser = ref.read(currentUserProvider).value;
    if (currentUser == null) return;

    final isBlocked = _controller.isUserBlocked(currentUser.uid);

    if (!mounted) return;

    final theme = Theme.of(context);

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: theme.brightness == Brightness.dark
              ? AppTheme.cardDark
              : AppTheme.cardLight,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: theme.brightness == Brightness.dark
                      ? Colors.grey.shade700
                      : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: Icon(
                  isBlocked ? Icons.block : Icons.block_outlined,
                  color: theme.colorScheme.error,
                ),
                title: Text(
                  isBlocked
                      ? 'Unblock ${widget.friend.username}'
                      : 'Block ${widget.friend.username}',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
                subtitle: Text(
                  isBlocked
                      ? 'You will be able to receive messages from this user'
                      : 'You will no longer receive messages from this user',
                ),
                onTap: () async {
                  Navigator.pop(context);
                  await _toggleBlockUser(currentUser.uid, isBlocked);
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _toggleBlockUser(String currentUserId, bool isBlocked) async {
    if (isBlocked) {
      await _controller.unblockUser(currentUserId);
    } else {
      await _controller.blockUser(currentUserId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final messagesAsync = ref.watch(messagesProvider(widget.chatId));
    final currentUser = ref.watch(currentUserProvider).value;
    final friendAsync = ref.watch(userStreamProvider(widget.friend.uid));

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isBlocked = currentUser != null
        ? _controller.isUserBlocked(currentUser.uid)
        : false;

    if (isBlocked) {
      return Scaffold(
        backgroundColor: isDark
            ? AppTheme.backgroundDark
            : AppTheme.backgroundLight,
        appBar: _buildAppBar(theme, isDark, isBlocked: true),
        body: BlockedUserView(
          username: widget.friend.username,
          onUnblock: () => _toggleBlockUser(currentUser.uid, true),
        ),
      );
    }

    return Scaffold(
      backgroundColor: isDark
          ? AppTheme.backgroundDark
          : AppTheme.backgroundLight,
      appBar: _buildAppBar(theme, isDark, friendAsync: friendAsync),
      body: Column(
        children: [
          Expanded(
            child: messagesAsync.when(
              data: (messages) {
                if (messages.isEmpty) {
                  return EmptyMessagesView(
                    friendUsername: widget.friend.username,
                  );
                }

                return Column(
                  children: [
                    Expanded(
                      child: ListView.builder(
                        key: const PageStorageKey('messages_list'),
                        controller: _scrollController,
                        reverse: true,
                        padding: const EdgeInsets.all(16),
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          final message = messages[index];
                          final isMe = message.senderId == currentUser?.uid;

                          return SwipeToReply(
                            key: ValueKey('swipe_${message.messageId}'),
                            onReply: () => _setReplyMessage(
                              message,
                              isMe ? 'You' : widget.friend.username,
                            ),
                            isMe: isMe,
                            child: MessageBubble(
                              key: ValueKey(message.messageId),
                              message: message,
                              isMe: isMe,
                              theme: theme,
                              isDark: isDark,
                              currentUserId: currentUser?.uid ?? '',
                              onReaction: _controller.addReaction,
                              onLongPress: _showMessageOptions,
                            ),
                          );
                        },
                      ),
                    ),
                    friendAsync.when(
                      data: (friend) {
                        if (friend != null &&
                            friend.isTyping &&
                            friend.typingInChatId == widget.chatId) {
                          return TypingIndicator(isDark: isDark);
                        }
                        return const SizedBox.shrink();
                      },
                      loading: () => const SizedBox.shrink(),
                      error: (_, _) => const SizedBox.shrink(),
                    ),
                  ],
                );
              },
              loading: () => Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(
                    theme.colorScheme.primary,
                  ),
                ),
              ),
              error: (error, stack) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.error.withValues(alpha: .1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.error_outline_rounded,
                          size: 48,
                          color: theme.colorScheme.error,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Unable to Load Messages',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        error.toString(),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: isDark
                              ? AppTheme.textSecondaryDark
                              : AppTheme.textSecondaryLight,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_replyToMessage != null && _replyToSenderName != null)
            ReplyPreview(
              replyToMessage: _replyToMessage!,
              senderName: _replyToSenderName!,
              onCancel: _cancelReply,
            ),
          // Slim upload progress bar — only shown during media/voice uploads.
          // Text messages are near-instant so no indicator is needed for them.
          if (_isUploadingMedia)
            LinearProgressIndicator(
              minHeight: 2,
              valueColor: AlwaysStoppedAnimation<Color>(
                theme.colorScheme.primary,
              ),
              backgroundColor:
                  theme.colorScheme.primary.withValues(alpha: 0.15),
            ),
          _buildMessageInput(theme, isDark),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(
    ThemeData theme,
    bool isDark, {
    bool isBlocked = false,
    AsyncValue<UserModel?>? friendAsync,
  }) {
    return AppBar(
      titleSpacing: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () => Navigator.pop(context),
      ),
      title: isBlocked
          ? Text(widget.friend.username)
          : friendAsync?.when(
                  data: (friend) {
                    if (friend == null) return Text(widget.friend.username);

                    return Row(
                      children: [
                        Stack(
                          children: [
                            UserAvatar(
                              imageUrl: friend.avatarUrl,
                              radius: 20,
                              showOnlineIndicator: false,
                            ),
                            if (friend.isOnline)
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: AppTheme.onlineGreen,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: theme.appBarTheme.backgroundColor!,
                                      width: 2,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                friend.username,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                friend.isTyping &&
                                        friend.typingInChatId == widget.chatId
                                    ? 'typing...'
                                    : friend.isOnline
                                    ? 'Online'
                                    : DateFormatter.formatOnlineStatus(
                                        friend.lastSeen,
                                      ),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 12,
                                  color:
                                      friend.isTyping &&
                                          friend.typingInChatId == widget.chatId
                                      ? theme.colorScheme.primary
                                      : friend.isOnline
                                      ? AppTheme.onlineGreen
                                      : (isDark
                                            ? AppTheme.textTertiaryDark
                                            : AppTheme.textTertiaryLight),
                                  fontStyle:
                                      friend.isTyping &&
                                          friend.typingInChatId == widget.chatId
                                      ? FontStyle.italic
                                      : FontStyle.normal,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                  loading: () => Row(
                    children: [
                      UserAvatar(imageUrl: widget.friend.avatarUrl, radius: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.friend.username,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  error: (_, _) => Row(
                    children: [
                      UserAvatar(imageUrl: widget.friend.avatarUrl, radius: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.friend.username,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ) ??
                Text(widget.friend.username),
      actions: isBlocked
          ? [
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                onSelected: (value) {
                  if (value == 'unblock') {
                    final currentUser = ref.read(currentUserProvider).value;
                    if (currentUser != null) {
                      _toggleBlockUser(currentUser.uid, true);
                    }
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'unblock',
                    child: Row(
                      children: [
                        Icon(
                          Icons.block,
                          size: 20,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Unblock User',
                          style: TextStyle(color: theme.colorScheme.primary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ]
          : [
              IconButton(
                icon: const Icon(Icons.call_rounded),
                onPressed: _controller.makeAudioCall,
                tooltip: 'Voice Call',
              ),
              IconButton(
                icon: const Icon(Icons.videocam_rounded),
                onPressed: _controller.makeVideoCall,
                tooltip: 'Video Call',
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                onSelected: (value) {
                  if (value == 'clear') {
                    _controller.clearConversation();
                  } else if (value == 'block') {
                    _showBlockOptions();
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'block',
                    child: Row(
                      children: [
                        Icon(
                          Icons.block_rounded,
                          size: 20,
                          color: theme.colorScheme.error,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Block User',
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'clear',
                    child: Row(
                      children: [
                        Icon(
                          Icons.delete_outline_rounded,
                          size: 20,
                          color: theme.colorScheme.error,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Clear Chat',
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
    );
  }

  Widget _buildMessageInput(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.cardDark : AppTheme.cardLight,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            IconButton(
              icon: Icon(
                Icons.add_circle_rounded,
                color: theme.colorScheme.primary,
                size: 28,
              ),
              onPressed: _showAttachmentOptions,
              tooltip: 'Attach file',
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF2A2A2A)
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: TextField(
                  controller: _messageController,
                  decoration: InputDecoration(
                    hintText: 'Message...',
                    hintStyle: TextStyle(
                      color: isDark
                          ? AppTheme.textTertiaryDark
                          : AppTheme.textTertiaryLight,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                  ),
                  style: theme.textTheme.bodyLarge,
                  maxLines: null,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (value) => setState(() {}),
                ),
              ),
            ),
            const SizedBox(width: 4),
            // Mic button (empty text) or send button (has text).
            // Never replaced by a spinner — the LinearProgressIndicator above
            // the input bar signals an ongoing upload without blocking input.
            if (_messageController.text.isEmpty)
              VoiceRecorderButton(onRecordingComplete: _sendVoiceMessage)
            else
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      theme.colorScheme.primary,
                      theme.colorScheme.primary.withValues(alpha: .8),
                    ],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: theme.colorScheme.primary.withValues(alpha: .3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: IconButton(
                  icon: const Icon(Icons.send_rounded, color: Colors.white),
                  onPressed: _sendTextMessage,
                  tooltip: 'Send',
                ),
              ),
          ],
        ),
      ),
    );
  }
}
