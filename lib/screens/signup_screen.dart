import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:vibetalk/core/app_string.dart';
import 'package:vibetalk/core/error_handler.dart';
import 'package:vibetalk/core/validator.dart';
import 'package:vibetalk/services/image_service.dart';
import 'package:vibetalk/widgets/custom_button.dart';
import 'package:vibetalk/widgets/custom_text_field.dart';
import 'package:vibetalk/widgets/loading_overlay.dart';

import '../../core/cloudinary_config.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';

// Constants
class SignUpConstants {
  static const double avatarRadius = 60.0;
  static const double cameraIconSize = 20.0;
  static const double spacing = 20.0;
  static const double largeSpacing = 32.0;
}


class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key});

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  File? _avatarImage;

  @override
  void dispose() {
    // ✅ OPTIMIZED: Proper cleanup
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();

    // Clear file reference
    if (_avatarImage != null) {
      _avatarImage = null;
    }

    super.dispose();
  }

  Future<void> _pickAvatar() async {
    if (_isLoading) return;

    try {
      await ImagePickerService.showImageSourceDialog(context, (file) async {
        if (file != null && await file.exists()) {
          if (mounted) {
            setState(() {
              _avatarImage = file;
            });
          }
        } else if (file != null) {
          if (mounted) {
            ErrorHandler.showErrorSnackBar(
              context,
              'Selected image file not found',
            );
          }
        }
      }, allowCrop: true);
    } catch (e) {
      if (mounted) {
        ErrorHandler.showErrorSnackBar(
          context,
          'Failed to select image: ${ErrorHandler.getErrorMessage(e)}',
        );
      }
    }
  }

  void _removeAvatar() {
    setState(() {
      _avatarImage = null;
    });
  }

  void _clearForm() {
    _usernameController.clear();
    _emailController.clear();
    _passwordController.clear();
    _confirmPasswordController.clear();
    setState(() {
      _avatarImage = null;
      _obscurePassword = true;
      _obscureConfirmPassword = true;
    });
  }

  Future<void> _signUp() async {
    if (!_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);

    try {
      String? avatarUrl;

      // Upload avatar if selected
      if (_avatarImage != null) {
        final tempUserId = DateTime.now().millisecondsSinceEpoch.toString();
        final storageRepo = ref.read(storageRepositoryProvider);
        avatarUrl = await storageRepo.uploadAvatar(tempUserId, _avatarImage!);
      }

      // Create user account
      await ref
          .read(authRepositoryProvider)
          .signUpWithEmailAndPassword(
            email: _emailController.text.trim(),
            password: _passwordController.text,
            username: _usernameController.text.trim(),
            avatarUrl: avatarUrl,
          );

      if (mounted) {
        _clearForm();
        setState(() => _isLoading = false);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Account created successfully!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return LoadingOverlay(
      isLoading: _isLoading,
      message: 'Creating your account...',
      child: Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 40),

                  // Title
                  Text(
                    'Create Account',
                    style: theme.textTheme.displayLarge?.copyWith(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? AppTheme.textPrimaryDark
                          : AppTheme.textPrimaryLight,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 8),

                  // Subtitle
                  Text(
                    'Sign up to get started',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: isDark
                          ? AppTheme.textSecondaryDark
                          : AppTheme.textSecondaryLight,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: SignUpConstants.largeSpacing),

                  // ✅ OPTIMIZED: Extracted avatar picker to reduce rebuilds
                  _AvatarPicker(
                    avatarImage: _avatarImage,
                    isLoading: _isLoading,
                    onPickAvatar: _pickAvatar,
                    onRemoveAvatar: _removeAvatar,
                    theme: theme,
                    isDark: isDark,
                  ),

                  const SizedBox(height: 8),

                  Text(
                    'Tap to add profile photo',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isDark
                          ? AppTheme.textSecondaryDark
                          : AppTheme.textSecondaryLight,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: SignUpConstants.largeSpacing),

                  // Username Field
                  CustomTextField(
                    controller: _usernameController,
                    label: AppStrings.username,
                    prefixIcon: Icons.person_outlined,
                    validator: Validators.validateUsername,
                    textInputAction: TextInputAction.next,
                    enabled: !_isLoading,
                  ),

                  const SizedBox(height: SignUpConstants.spacing),

                  // Email Field
                  CustomTextField(
                    controller: _emailController,
                    label: AppStrings.email,
                    prefixIcon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                    validator: Validators.validateEmail,
                    textInputAction: TextInputAction.next,
                    enabled: !_isLoading,
                  ),

                  const SizedBox(height: SignUpConstants.spacing),

                  // Password Field
                  CustomTextField(
                    controller: _passwordController,
                    label: AppStrings.password,
                    prefixIcon: Icons.lock_outlined,
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.next,
                    enabled: !_isLoading,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () {
                        setState(() => _obscurePassword = !_obscurePassword);
                      },
                      tooltip: _obscurePassword
                          ? 'Show password'
                          : 'Hide password',
                    ),
                    validator: Validators.validatePassword,
                  ),

                  const SizedBox(height: SignUpConstants.spacing),

                  // Confirm Password Field
                  CustomTextField(
                    controller: _confirmPasswordController,
                    label: AppStrings.confirmPassword,
                    prefixIcon: Icons.lock_outlined,
                    obscureText: _obscureConfirmPassword,
                    textInputAction: TextInputAction.done,
                    enabled: !_isLoading,
                    onFieldSubmitted: (_) => _signUp(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirmPassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () {
                        setState(
                          () => _obscureConfirmPassword =
                              !_obscureConfirmPassword,
                        );
                      },
                      tooltip: _obscureConfirmPassword
                          ? 'Show password'
                          : 'Hide password',
                    ),
                    validator: (value) => Validators.validateConfirmPassword(
                      value,
                      _passwordController.text,
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Sign Up Button
                  CustomButton(
                    text: AppStrings.signUp,
                    onPressed: _isLoading ? () {} : _signUp,
                    isLoading: _isLoading,
                  ),

                  const SizedBox(height: 24),

                  // Divider with "OR"
                  Row(
                    children: [
                      Expanded(
                        child: Divider(
                          color: isDark
                              ? Colors.grey.shade800
                              : Colors.grey.shade300,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'OR',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: isDark
                                ? AppTheme.textSecondaryDark
                                : AppTheme.textSecondaryLight,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Divider(
                          color: isDark
                              ? Colors.grey.shade800
                              : Colors.grey.shade300,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Sign In Link
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        AppStrings.alreadyHaveAccount,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: isDark
                              ? AppTheme.textSecondaryDark
                              : AppTheme.textSecondaryLight,
                        ),
                      ),
                      TextButton(
                        onPressed: _isLoading
                            ? null
                            : () {
                                Navigator.of(context).pop();
                              },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                        ),
                        child: Text(
                          AppStrings.signInHere,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ✅ OPTIMIZED: Extracted avatar picker to separate widget
class _AvatarPicker extends StatelessWidget {
  final File? avatarImage;
  final bool isLoading;
  final VoidCallback onPickAvatar;
  final VoidCallback onRemoveAvatar;
  final ThemeData theme;
  final bool isDark;

  const _AvatarPicker({
    required this.avatarImage,
    required this.isLoading,
    required this.onPickAvatar,
    required this.onRemoveAvatar,
    required this.theme,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Stack(
        children: [
          GestureDetector(
            onTap: isLoading ? null : onPickAvatar,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: .1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: CircleAvatar(
                key: ValueKey(avatarImage?.path ?? 'no_image'),
                radius: SignUpConstants.avatarRadius,
                backgroundColor: theme.colorScheme.primary.withValues(
                  alpha: .1,
                ),
                backgroundImage: avatarImage != null
                    ? FileImage(avatarImage!)
                    : null,
                child: avatarImage == null
                    ? Icon(
                        Icons.person_outlined,
                        size: SignUpConstants.avatarRadius,
                        color: theme.colorScheme.primary,
                      )
                    : null,
              ),
            ),
          ),

          // Remove Button
          if (avatarImage != null)
            Positioned(
              top: 0,
              right: 0,
              child: GestureDetector(
                onTap: isLoading ? null : onRemoveAvatar,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.error,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 16),
                ),
              ),
            ),

          // Camera Button
          Positioned(
            bottom: 0,
            right: 0,
            child: GestureDetector(
              onTap: isLoading ? null : onPickAvatar,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: .2),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.camera_alt,
                  color: Colors.white,
                  size: SignUpConstants.cameraIconSize,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
