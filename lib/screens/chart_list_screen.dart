
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:vibetalk/core/date_formattor.dart';
import 'package:vibetalk/models/chart_model.dart';
import 'package:vibetalk/providers/chart_provider.dart';
import 'package:vibetalk/providers/user_cache_provider.dart';

import 'package:vibetalk/screens/Conservation/conversation_screen.dart';
import 'package:vibetalk/widgets/empty_state.dart';
import 'package:vibetalk/widgets/user_avatar.dart';

import '../../providers/auth_provider.dart';
import '../../models/user_model.dart';

import '../../theme/app_theme.dart';


class ChatListScreen extends ConsumerStatefulWidget {
  const ChatListScreen({super.key});

  @override
  ConsumerState<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends ConsumerState<ChatListScreen> {
  // Optimistic removal set — hides chats that were swiped away but not yet
  // deleted from Firestore (allows undo without a Firestore read).
  final Set<String> _dismissedChatIds = {};

  void _onDeleteChat(String chatId, String friendName) {
    setState(() => _dismissedChatIds.add(chatId));

    bool undone = false;

    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();

    messenger
        .showSnackBar(
          SnackBar(
            content: Text('Conversation with $friendName deleted'),
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.grey.shade900,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            action: SnackBarAction(
              label: 'UNDO',
              textColor: Colors.redAccent,
              onPressed: () {
                undone = true;
                setState(() => _dismissedChatIds.remove(chatId));
              },
            ),
          ),
        )
        .closed
        .then((_) {
          if (!undone) {
            ref.read(chatServiceProvider).deleteChat(chatId).catchError(
              (e) => debugPrint('❌ Delete chat error: $e'),
            );
            // DO NOT remove chatId from _dismissedChatIds here.
            // Removing it before Firestore confirms deletion causes a 1-second
            // flash where the deleted chat reappears. The stale entry is cleaned
            // up lazily in build() once Firestore stream no longer includes it.
          }
        });
  }

  Future<void> _confirmDeleteChat(
    BuildContext ctx,
    String chatId,
    String friendName,
  ) async {
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Conversation'),
        content: Text(
          'Delete your conversation with $friendName? '
          'This cannot be undone for the other person.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) _onDeleteChat(chatId, friendName);
  }

  @override
  Widget build(BuildContext context) {
    final chatsAsync = ref.watch(chatListProvider);
    final currentUser = ref.watch(currentUserProvider).value;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: const Text('Chats'), elevation: 0),
      body: chatsAsync.when(
        data: (allChats) {
          // Clean up stale dismissed IDs — chats that Firestore has already
          // removed from the list no longer need to be tracked.
          _dismissedChatIds.removeWhere(
            (id) => !allChats.any((c) => c.chatId == id),
          );

          // Filter out optimistically-dismissed chats
          final chats = allChats
              .where((c) => !_dismissedChatIds.contains(c.chatId))
              .toList();

          if (chats.isEmpty) {
            return const EmptyState(
              icon: Icons.chat_bubble_outline,
              message: 'No chats yet',
              subtitle: 'Start chatting with your friends',
            );
          }

          return ListView.separated(
            key: const PageStorageKey('chat_list'),
            itemCount: chats.length,
            separatorBuilder: (context, index) => Divider(
              height: 1,
              indent: 72,
              color: isDark
                  ? Colors.grey.shade800.withValues(alpha: .5)
                  : Colors.grey.shade200,
            ),
            itemBuilder: (context, index) {
              final chat = chats[index];
              final friendId = chat.participants.firstWhere(
                (id) => id != currentUser?.uid,
              );

              final friendName =
                  chat.participantsData?[friendId]?['username'] as String? ??
                  'Unknown';

              return _SwipeToDeleteWrapper(
                key: ValueKey('swipe_${chat.chatId}'),
                chatId: chat.chatId,
                onDelete: () => _onDeleteChat(chat.chatId, friendName),
                onLongPress: () =>
                    _confirmDeleteChat(context, chat.chatId, friendName),
                child: _ChatListItem(
                  key: ValueKey(chat.chatId),
                  chat: chat,
                  friendId: friendId,
                  currentUserId: currentUser?.uid,
                  theme: theme,
                  isDark: isDark,
                ),
              );
            },
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
                Icon(
                  Icons.error_outline,
                  size: 64,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  'Error Loading Chats',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: isDark
                        ? AppTheme.textPrimaryDark
                        : AppTheme.textPrimaryLight,
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
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () => ref.invalidate(chatListProvider),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Swipe-to-delete wrapper
// ---------------------------------------------------------------------------

class _SwipeToDeleteWrapper extends ConsumerWidget {
  final String chatId;
  final Widget child;
  final VoidCallback onDelete;
  final VoidCallback onLongPress;

  const _SwipeToDeleteWrapper({
    super.key,
    required this.chatId,
    required this.child,
    required this.onDelete,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dismissible(
      key: ValueKey('dismissible_$chatId'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFFF5252), Color(0xFFD32F2F)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.6, end: 1.0),
              duration: const Duration(milliseconds: 300),
              curve: Curves.elasticOut,
              builder: (ctx, scale, child) =>
                  Transform.scale(scale: scale, child: child),
              child: const Icon(
                Icons.delete_rounded,
                color: Colors.white,
                size: 28,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Delete',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
      // onDismissed fires AFTER the slide-away animation completes.
      // Using onDismissed (not confirmDismiss) prevents a double-removal:
      // confirmDismiss+return true would remove the widget from the tree AND
      // _dismissedChatIds would also hide it, causing a layout jump.
      onDismissed: (_) => onDelete(),
      child: GestureDetector(
        onLongPress: onLongPress,
        child: child,
      ),
    );
  }
}


// ✅ OPTIMIZED: Extracted to separate widget to prevent rebuilds
class _ChatListItem extends ConsumerWidget {
  final ChatModel chat;
  final String friendId;
  final String? currentUserId;
  final ThemeData theme;
  final bool isDark;

  const _ChatListItem({
    super.key,
    required this.chat,
    required this.friendId,
    required this.currentUserId,
    required this.theme,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final participantData = chat.participantsData?[friendId];

    // Always watch fresh user data so avatar updates are reflected immediately.
    // participantsData.avatarUrl can be stale (set at chat creation time).
    // userCacheProvider keeps data for 5 min — fast after first fetch.
    final friendAsync = ref.watch(userCacheProvider(friendId));
    final freshUser = friendAsync.asData?.value;

    if (participantData != null) {
      return _buildChatTile(
        context,
        username:
            participantData['username'] as String? ??
            freshUser?.username ??
            'Unknown',
        // Fresh avatar overrides stale cached value.
        // Falls back to cached if Firestore hasn't responded yet.
        avatarUrl:
            freshUser?.avatarUrl ?? participantData['avatarUrl'] as String?,
        isOnline: freshUser?.isOnline ?? false,
      );
    }

    // Fallback: no participantsData at all — wait for userCacheProvider
    return friendAsync.when(
      data: (friend) {
        if (friend == null) return const SizedBox.shrink();
        return _buildChatTile(
          context,
          username: friend.username,
          avatarUrl: friend.avatarUrl,
          isOnline: friend.isOnline,
        );
      },
      loading: () => _buildLoadingTile(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }

  Widget _buildChatTile(
    BuildContext context, {
    required String username,
    required String? avatarUrl,
    required bool isOnline,
  }) {
    final unreadCount = chat.unreadCount[currentUserId] ?? 0;
    final hasUnread = unreadCount > 0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ConversationScreen(
                chatId: chat.chatId,
                friend: UserModel(
                  uid: friendId,
                  username: username,
                  email: '',
                  avatarUrl: avatarUrl,
                  isOnline: isOnline,
                  fcmToken: '',
                  createdAt: DateTime.now(),
                  searchKeywords: [],
                ),
              ),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // Avatar
              UserAvatar(
                imageUrl: avatarUrl,
                showOnlineIndicator: true,
                isOnline: isOnline,
                radius: 28,
              ),

              const SizedBox(width: 12),

              // Chat Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Username
                    Text(
                      username,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: hasUnread
                            ? FontWeight.w700
                            : FontWeight.w600,
                        color: isDark
                            ? AppTheme.textPrimaryDark
                            : AppTheme.textPrimaryLight,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),

                    const SizedBox(height: 4),

                    // Last Message
                    Text(
                      chat.lastMessage ?? 'No messages yet',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: hasUnread
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: hasUnread
                            ? (isDark
                                  ? AppTheme.textPrimaryDark
                                  : AppTheme.textPrimaryLight)
                            : (isDark
                                  ? AppTheme.textSecondaryDark
                                  : AppTheme.textSecondaryLight),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // Time and Unread Badge
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Time
                  if (chat.lastMessageTime != null)
                    Text(
                      DateFormatter.formatChatTime(chat.lastMessageTime!),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 12,
                        fontWeight: hasUnread
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: hasUnread
                            ? theme.colorScheme.primary
                            : (isDark
                                  ? AppTheme.textSecondaryDark
                                  : AppTheme.textSecondaryLight),
                      ),
                    ),

                  // Unread Badge
                  if (hasUnread) ...[
                    const SizedBox(height: 6),
                    Container(
                      constraints: const BoxConstraints(
                        minWidth: 20,
                        minHeight: 20,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        unreadCount > 99 ? '99+' : '$unreadCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingTile() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    theme.colorScheme.primary,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 16,
                  width: 120,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  height: 14,
                  width: 180,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(4),
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
