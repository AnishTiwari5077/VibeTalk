// lib/screens/friend_profile_screen.dart
//
// Read-only profile view of a friend.
// Opened by tapping the avatar in the ConversationScreen AppBar.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibetalk/core/date_formattor.dart';
import 'package:vibetalk/models/user_model.dart';
import 'package:vibetalk/providers/user_provider.dart';
import 'package:vibetalk/theme/app_theme.dart';
import 'package:vibetalk/widgets/user_avatar.dart';

class FriendProfileScreen extends ConsumerWidget {
  final UserModel friend;

  const FriendProfileScreen({super.key, required this.friend});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final friendAsync = ref.watch(userStreamProvider(friend.uid));
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Use fresh Firestore data, fall back to the snapshot passed in.
    final user = friendAsync.asData?.value ?? friend;

    return Scaffold(
      backgroundColor:
          isDark ? AppTheme.backgroundDark : AppTheme.backgroundLight,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          // ── Gradient header with avatar ─────────────────────────────────
          SliverToBoxAdapter(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Gradient header
                Container(
                  height: 240,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        theme.colorScheme.primary,
                        theme.colorScheme.primary.withValues(alpha: 0.8),
                        theme.colorScheme.secondary,
                      ],
                    ),
                  ),
                  child: Stack(
                    children: [
                      // Decorative circles
                      Positioned(
                        top: -30,
                        left: -30,
                        child: Container(
                          width: 160,
                          height: 160,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.06),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 40,
                        right: -40,
                        child: Container(
                          width: 200,
                          height: 200,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.04),
                          ),
                        ),
                      ),
                      // Back button
                      Positioned(
                        top: 0,
                        left: 0,
                        child: SafeArea(
                          child: IconButton(
                            icon: const Icon(
                              Icons.arrow_back_rounded,
                              color: Colors.white,
                            ),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ),
                      ),
                      // Title
                      const Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: SafeArea(
                          child: Center(
                            child: Padding(
                              padding: EdgeInsets.only(top: 14),
                              child: Text(
                                'Profile',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Avatar — overlaps header bottom
                Positioned(
                  bottom: -60,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: theme.scaffoldBackgroundColor,
                          width: 4,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color:
                                theme.colorScheme.primary.withValues(alpha: 0.3),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Hero(
                        tag: 'friend_avatar_${friend.uid}',
                        child: UserAvatar(
                          imageUrl: user.avatarUrl,
                          radius: 60,
                          showOnlineIndicator: false,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Content ─────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 80, 24, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Username
                  Text(
                    user.username,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.3,
                      color: isDark
                          ? AppTheme.textPrimaryDark
                          : AppTheme.textPrimaryLight,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Online status pill
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: user.isOnline
                          ? AppTheme.onlineGreen.withValues(alpha: 0.12)
                          : (isDark
                                ? Colors.grey.shade800
                                : Colors.grey.shade100),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: user.isOnline
                                ? AppTheme.onlineGreen
                                : Colors.grey,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          user.isOnline
                              ? 'Online'
                              : DateFormatter.formatOnlineStatus(user.lastSeen),
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: user.isOnline
                                ? AppTheme.onlineGreen
                                : (isDark
                                      ? AppTheme.textSecondaryDark
                                      : AppTheme.textSecondaryLight),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Info cards
                  _InfoCard(
                    icon: Icons.person_rounded,
                    iconColor: Colors.blue,
                    title: 'Username',
                    subtitle: user.username,
                    theme: theme,
                    isDark: isDark,
                  ),
                  const SizedBox(height: 12),
                  _InfoCard(
                    icon: Icons.calendar_today_rounded,
                    iconColor: Colors.purple,
                    title: 'Member Since',
                    subtitle: _formatDate(user.createdAt),
                    theme: theme,
                    isDark: isDark,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final ThemeData theme;
  final bool isDark;

  const _InfoCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.theme,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.cardDark : AppTheme.cardLight,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: iconColor, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: isDark
                          ? AppTheme.textSecondaryDark
                          : AppTheme.textSecondaryLight,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? AppTheme.textPrimaryDark
                          : AppTheme.textPrimaryLight,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
