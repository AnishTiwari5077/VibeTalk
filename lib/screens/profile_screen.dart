// lib/screens/profile/profile_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:new_chart/core/env_config.dart';
import 'package:new_chart/core/error_handler.dart';
import 'package:new_chart/widgets/loading_overlay.dart';
import 'package:new_chart/widgets/profile_edit_dialog.dart';
import 'package:new_chart/widgets/user_avatar.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/storage_repository.dart';
import '../../theme/app_theme.dart';

class ProfileConstants {
  static const double avatarRadius = 60.0;
  static const double editAvatarRadius = 50.0;
  static const double spacing = 24.0;
  static const double cardSpacing = 12.0;
  static const double buttonPaddingHorizontal = 32.0;
  static const double buttonPaddingVertical = 12.0;
}

final storageRepositoryProvider = Provider<StorageRepository>((ref) {
  return StorageRepository(
    cloudName: EnvConfig.cloudinaryCloudName,
    uploadPreset: EnvConfig.cloudinaryUploadPreset,
  );
});

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _isLoading = false;

  Future<void> _editProfile() async {
    final currentUser = ref.read(currentUserProvider).value;
    if (currentUser == null) return;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => EditProfileDialog(user: currentUser),
    );

    if (result == true) {
      ref.invalidate(currentUserProvider);
    }
  }

  Future<void> _logout() async {
    final confirm = await ErrorHandler.showConfirmDialog(
      context,
      'Logout',
      'Are you sure you want to logout?',
    );

    if (!confirm) return;

    setState(() => _isLoading = true);

    try {
      // Use the auth service that properly handles logout
      await ref.read(authServiceProvider).logout();
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ErrorHandler.showErrorSnackBar(
          context,
          ErrorHandler.getErrorMessage(e),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserAsync = ref.watch(currentUserProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return LoadingOverlay(
      isLoading: _isLoading,
      message: 'Logging out...',
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Profile'),
          actions: [
            IconButton(
              icon: const Icon(Icons.logout_outlined),
              onPressed: _isLoading ? null : _logout,
              tooltip: 'Logout',
            ),
          ],
        ),
        body: currentUserAsync.when(
          data: (user) {
            if (user == null) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.person_off_outlined,
                      size: 64,
                      color: isDark
                          ? AppTheme.textSecondaryDark
                          : AppTheme.textSecondaryLight,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'User not found',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: isDark
                            ? AppTheme.textSecondaryDark
                            : AppTheme.textSecondaryLight,
                      ),
                    ),
                  ],
                ),
              );
            }

            return SingleChildScrollView(
              padding: const EdgeInsets.all(ProfileConstants.spacing),
              child: Column(
                children: [
                  const SizedBox(height: 20),

                  // Avatar with edit indicator
                  Stack(
                    children: [
                      UserAvatar(
                        imageUrl: user.avatarUrl,
                        radius: ProfileConstants.avatarRadius,
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: theme.scaffoldBackgroundColor,
                              width: 3,
                            ),
                          ),
                          child: const Icon(
                            Icons.edit,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Username
                  Text(
                    user.username,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? AppTheme.textPrimaryDark
                          : AppTheme.textPrimaryLight,
                    ),
                  ),

                  const SizedBox(height: 4),

                  // Email
                  Text(
                    user.email,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: isDark
                          ? AppTheme.textSecondaryDark
                          : AppTheme.textSecondaryLight,
                    ),
                  ),

                  const SizedBox(height: ProfileConstants.spacing),

                  // Status Card
                  _buildStatusCard(user.isOnline, theme, isDark),

                  const SizedBox(height: ProfileConstants.cardSpacing),

                  // Info Cards
                  _buildInfoCard(
                    icon: Icons.person_outlined,
                    title: 'Username',
                    subtitle: user.username,
                    theme: theme,
                    isDark: isDark,
                  ),

                  const SizedBox(height: ProfileConstants.cardSpacing),

                  _buildInfoCard(
                    icon: Icons.email_outlined,
                    title: 'Email',
                    subtitle: user.email,
                    theme: theme,
                    isDark: isDark,
                  ),

                  const SizedBox(height: ProfileConstants.spacing * 1.5),

                  // Edit Profile Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _editProfile,
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      label: const Text('Edit Profile'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: ProfileConstants.buttonPaddingHorizontal,
                          vertical: ProfileConstants.buttonPaddingVertical,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Member Since
                  Text(
                    'Member since ${user.createdAt.year}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isDark
                          ? AppTheme.textSecondaryDark
                          : AppTheme.textSecondaryLight,
                    ),
                  ),
                ],
              ),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
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
                    'Error Loading Profile',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: isDark
                          ? AppTheme.textPrimaryDark
                          : AppTheme.textPrimaryLight,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    ErrorHandler.getErrorMessage(error),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: isDark
                          ? AppTheme.textSecondaryDark
                          : AppTheme.textSecondaryLight,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () => ref.invalidate(currentUserProvider),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required ThemeData theme,
    required bool isDark,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
          width: 1,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: theme.colorScheme.primary, size: 24),
        ),
        title: Text(
          title,
          style: theme.textTheme.labelLarge?.copyWith(
            color: isDark
                ? AppTheme.textSecondaryDark
                : AppTheme.textSecondaryLight,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            subtitle,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: isDark
                  ? AppTheme.textPrimaryDark
                  : AppTheme.textPrimaryLight,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusCard(bool isOnline, ThemeData theme, bool isDark) {
    final statusColor = isOnline ? Colors.green : Colors.grey;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
          width: 1,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(Icons.circle, color: statusColor, size: 24),
        ),
        title: Text(
          'Status',
          style: theme.textTheme.labelLarge?.copyWith(
            color: isDark
                ? AppTheme.textSecondaryDark
                : AppTheme.textSecondaryLight,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            isOnline ? 'Online' : 'Offline',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: isDark
                  ? AppTheme.textPrimaryDark
                  : AppTheme.textPrimaryLight,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
