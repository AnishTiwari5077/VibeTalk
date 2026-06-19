import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibetalk/core/error_handler.dart';
import 'package:vibetalk/models/user_model.dart';
import 'package:vibetalk/providers/auth_provider.dart';
import 'package:vibetalk/providers/chart_provider.dart';
import 'package:vibetalk/providers/friend_req_provider.dart';
import 'package:vibetalk/screens/Conservation/conversation_screen.dart';
import 'package:vibetalk/widgets/empty_state.dart';
import 'package:vibetalk/widgets/user_avatar.dart';

import '../../theme/app_theme.dart';

import '../../providers/user_provider.dart';

class UsersListScreen extends ConsumerStatefulWidget {
  const UsersListScreen({super.key});

  @override
  ConsumerState<UsersListScreen> createState() => _UsersListScreenState();
}

class _UsersListScreenState extends ConsumerState<UsersListScreen> {
  final _searchController = TextEditingController();
  bool _isNavigating = false; // prevents double-tap opening two conversations

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _sendFriendRequest(String userId) async {
    try {
      final confirm = await ErrorHandler.showConfirmDialog(
        context,
        'Send Friend Request',
        'Do you want to send a friend request to this user?',
      );

      if (!confirm) return;

      await ref.read(friendRequestProvider).sendFriendRequest(userId);

      if (mounted) {
        ErrorHandler.showSuccessSnackBar(
          context,
          'Friend request sent successfully',
        );
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.showErrorSnackBar(
          context,
          ErrorHandler.getErrorMessage(e),
        );
      }
    }
  }

  Future<void> _unfriend(String userId, String username) async {
    try {
      final confirm = await _showUnfriendDialog(username);

      if (!confirm) return;

      await ref.read(friendRequestProvider).unfriend(userId, username);

      if (mounted) {
        ErrorHandler.showSuccessSnackBar(context, 'Unfriended $username');
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.showErrorSnackBar(
          context,
          ErrorHandler.getErrorMessage(e),
        );
      }
    }
  }

  /// Opens an existing conversation or creates a new one if the chat document
  /// was deleted. This is the entry point when a friend taps "Message".
  Future<void> _openConversation(String userId, String username) async {
    // Guard against double-tap pushing two routes.
    if (_isNavigating) return;
    _isNavigating = true;

    try {
      final currentUserId = ref.read(currentUserProvider).value?.uid ?? '';

      // Compute chatId locally — same algorithm as ChatService.generateChatId.
      // This avoids any Firestore round-trip, so navigation is instant.
      final chatId = currentUserId.compareTo(userId) <= 0
          ? '${currentUserId}_$userId'
          : '${userId}_$currentUserId';

      // Get fresh user data from the already-loaded list (no network).
      final users = ref.read(filteredUsersProvider).value ?? [];
      final friend = users.firstWhere(
        (u) => u.uid == userId,
        orElse: () => UserModel(
          uid: userId,
          username: username,
          email: '',
          fcmToken: '',
          createdAt: DateTime.now(),
          searchKeywords: [],
        ),
      );

      // Navigate immediately — zero delay.
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ConversationScreen(chatId: chatId, friend: friend),
        ),
      );

      // After returning from the screen, ensure the chat document exists.
      // Only does real work when BOTH users previously deleted the conversation;
      // for normal friends the doc is already there so this is a cheap GET.
      if (mounted) {
        ref
            .read(chatServiceProvider)
            .getOrCreateChat(userId)
            .catchError((_) => ''); // background; errors silently ignored
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.showErrorSnackBar(
          context,
          ErrorHandler.getErrorMessage(e),
        );
      }
    } finally {
      if (mounted) _isNavigating = false;
    }
  }

  Future<bool> _showUnfriendDialog(String username) async {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                Icon(Icons.warning_rounded, color: Colors.orange, size: 28),
                const SizedBox(width: 12),
                const Text('Unfriend User'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Are you sure you want to unfriend $username?',
                  style: theme.textTheme.bodyLarge,
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.orange.withValues(alpha: 0.1)
                        : Colors.orange.withValues(alpha: .05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.orange.withValues(alpha: .3),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'This action will:',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: Colors.orange.shade700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildWarningItem(
                        theme,
                        Icons.chat_bubble_outline,
                        'Delete all chat messages',
                      ),
                      const SizedBox(height: 4),
                      _buildWarningItem(
                        theme,
                        Icons.person_remove_outlined,
                        'Remove from your friends list',
                      ),
                      const SizedBox(height: 4),
                      _buildWarningItem(
                        theme,
                        Icons.block,
                        'This cannot be undone',
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
                child: Text(
                  'Cancel',
                  style: TextStyle(
                    color: isDark
                        ? AppTheme.textPrimaryDark
                        : AppTheme.textPrimaryLight,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  'Unfriend',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ) ??
        false;
  }

  Widget _buildWarningItem(ThemeData theme, IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.orange.shade700),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.orange.shade700,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final usersAsync = ref.watch(filteredUsersProvider);
    final sentRequests = ref.watch(sentRequestsProvider).value ?? [];
    // Use accepted friend requests — not chats — to determine isFriend.
    // This stays TRUE even when both users delete the conversation.
    final acceptedFriends = ref.watch(acceptedFriendsProvider).value ?? {};
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: const Text('Find Friends'), elevation: 0),
      body: Column(
        children: [
          // Search Bar
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            decoration: BoxDecoration(
              color: theme.appBarTheme.backgroundColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search users...',
                hintStyle: TextStyle(
                  color: isDark
                      ? AppTheme.textSecondaryDark
                      : AppTheme.textSecondaryLight,
                ),
                prefixIcon: Icon(
                  Icons.search,
                  color: isDark
                      ? AppTheme.textSecondaryDark
                      : AppTheme.textSecondaryLight,
                ),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          ref.read(searchQueryProvider.notifier).clear();
                          setState(() {});
                        },
                      )
                    : null,
                filled: true,
                fillColor: isDark ? Colors.grey.shade900 : Colors.grey.shade100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
              onChanged: (value) {
                ref.read(searchQueryProvider.notifier).set(value);
                setState(() {});
              },
            ),
          ),

          // Users List
          Expanded(
            child: usersAsync.when(
              data: (users) {
                if (users.isEmpty) {
                  return const EmptyState(
                    icon: Icons.people_outline,
                    message: 'No users found',
                    subtitle: 'Try searching with a different keyword',
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(filteredUsersProvider);
                  },
                  child: ListView.separated(
                    itemCount: users.length,
                    separatorBuilder: (context, index) => Divider(
                      height: 1,
                      indent: 72,
                      color: isDark
                          ? Colors.grey.shade800.withValues(alpha: .5)
                          : Colors.grey.shade200,
                    ),
                    itemBuilder: (context, index) {
                      final user = users[index];

                      // Check if request already sent
                      final requestSent = sentRequests.any(
                        (req) => req.receiverId == user.uid,
                      );

                      // isFriend is based on accepted friend requests,
                      // NOT on chat existence. Fixes the "no way to message
                      // after deleting conversation" bug.
                      final isFriend = acceptedFriends.contains(user.uid);

                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: isFriend
                              ? () => _openConversation(user.uid, user.username)
                              : requestSent
                              ? null
                              : () => _sendFriendRequest(user.uid),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            child: Row(
                              children: [
                                // Avatar
                                UserAvatar(
                                  imageUrl: user.avatarUrl,
                                  showOnlineIndicator: true,
                                  isOnline: user.isOnline,
                                  radius: 28,
                                ),

                                const SizedBox(width: 12),

                                // User Info
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      // Username
                                      Text(
                                        user.username,
                                        style: theme.textTheme.bodyLarge
                                            ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                              color: isDark
                                                  ? AppTheme.textPrimaryDark
                                                  : AppTheme.textPrimaryLight,
                                            ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),

                                      const SizedBox(height: 4),

                                      // Status
                                      Row(
                                        children: [
                                          Container(
                                            width: 8,
                                            height: 8,
                                            decoration: BoxDecoration(
                                              color: user.isOnline
                                                  ? Colors.green
                                                  : Colors.grey,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            user.isOnline
                                                ? 'Online'
                                                : 'Offline',
                                            style: theme.textTheme.bodySmall?.copyWith(
                                              color: user.isOnline
                                                  ? Colors.green
                                                  : (isDark
                                                        ? AppTheme
                                                              .textSecondaryDark
                                                        : AppTheme
                                                              .textSecondaryLight),
                                              fontWeight: user.isOnline
                                                  ? FontWeight.w600
                                                  : FontWeight.w400,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),

                                const SizedBox(width: 8),

                                // Action Button/Chip
                                _buildActionWidget(
                                  context,
                                  theme,
                                  isDark,
                                  isFriend,
                                  requestSent,
                                  user.uid,
                                  user.username,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
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
                        'Error Loading Users',
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
                        onPressed: () => ref.invalidate(filteredUsersProvider),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionWidget(
    BuildContext context,
    ThemeData theme,
    bool isDark,
    bool isFriend,
    bool requestSent,
    String userId,
    String username,
  ) {
    if (isFriend) {
      return PopupMenuButton<String>(
        onSelected: (value) {
          if (value == 'message') {
            _openConversation(userId, username);
          } else if (value == 'unfriend') {
            _unfriend(userId, username);
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            value: 'message',
            child: Row(
              children: [
                Icon(
                  Icons.chat_bubble_outline,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Text(
                  'Message',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
          const PopupMenuDivider(),
          PopupMenuItem(
            value: 'unfriend',
            child: Row(
              children: [
                Icon(Icons.person_remove, size: 20, color: Colors.red),
                const SizedBox(width: 12),
                Text('Unfriend', style: TextStyle(color: Colors.red)),
              ],
            ),
          ),
        ],
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: theme.colorScheme.primary.withValues(alpha: .3),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.check_circle,
                size: 16,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 4),
              Text(
                'Friends',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.arrow_drop_down,
                size: 18,
                color: theme.colorScheme.primary,
              ),
            ],
          ),
        ),
      );
    }

    if (requestSent) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.schedule,
              size: 16,
              color: isDark
                  ? AppTheme.textSecondaryDark
                  : AppTheme.textSecondaryLight,
            ),
            const SizedBox(width: 4),
            Text(
              'Pending',
              style: theme.textTheme.labelSmall?.copyWith(
                color: isDark
                    ? AppTheme.textSecondaryDark
                    : AppTheme.textSecondaryLight,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    return ElevatedButton.icon(
      onPressed: () => _sendFriendRequest(userId),
      icon: const Icon(Icons.person_add, size: 18),
      label: const Text('Add'),
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        minimumSize: const Size(0, 36),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}
