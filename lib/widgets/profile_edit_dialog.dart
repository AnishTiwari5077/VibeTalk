import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibetalk/core/error_handler.dart';
import 'package:vibetalk/core/validator.dart';
import 'package:vibetalk/models/user_model.dart';
import 'package:vibetalk/providers/auth_provider.dart';
import 'package:vibetalk/services/image_service.dart';
import 'package:vibetalk/theme/app_theme.dart';
import 'package:vibetalk/widgets/loading_overlay.dart';
import 'package:vibetalk/core/cloudinary_config.dart';

class EditProfileDialog extends ConsumerStatefulWidget {
  final UserModel user;

  const EditProfileDialog({super.key, required this.user});

  @override
  ConsumerState<EditProfileDialog> createState() => _EditProfileDialogState();
}

class _EditProfileDialogState extends ConsumerState<EditProfileDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _usernameController;
  bool _isLoading = false;
  File? _newAvatar;

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController(text: widget.user.username);
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _newAvatar = null;
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    if (_isLoading) return;

    try {
      await ImagePickerService.showImageSourceDialog(context, (file) {
        if (file != null && mounted) {
          setState(() => _newAvatar = file);
        }
      }, allowCrop: true);
    } catch (e) {
      if (mounted) {
        ErrorHandler.showErrorSnackBar(
          context,
          'Failed to pick image: ${ErrorHandler.getErrorMessage(e)}',
        );
      }
    }
  }

  void _removeAvatar() {
    if (_isLoading) return;
    setState(() => _newAvatar = null);
  }

  bool _hasChanges() {
    final usernameChanged =
        _usernameController.text.trim() != widget.user.username;
    final avatarChanged = _newAvatar != null;
    return usernameChanged || avatarChanged;
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) return;

    if (!_hasChanges()) {
      Navigator.of(context).pop(false);
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);

    try {
      final userRepo = ref.read(userRepositoryProvider);
      final storageRepo = ref.read(storageRepositoryProvider);

      final newUsername = _usernameController.text.trim();
      if (newUsername != widget.user.username && newUsername.isNotEmpty) {
        await userRepo.updateUsername(widget.user.uid, newUsername);
      }

      if (_newAvatar != null) {
        final avatarUrl = await storageRepo.uploadAvatar(
          widget.user.uid,
          _newAvatar!,
        );
        await userRepo.updateAvatar(widget.user.uid, avatarUrl);
      }

      if (mounted) {
        Navigator.of(context).pop(true);
        ErrorHandler.showSuccessSnackBar(
          context,
          'Profile updated successfully',
        );
      }
    } catch (e) {
      if (mounted) {
        String errorMessage = 'Failed to update profile';

        if (e is NetworkException) {
          errorMessage = 'Network error: ${e.message}';
        } else if (e is ValidationException) {
          errorMessage = 'Validation error: ${e.message}';
        } else {
          errorMessage = ErrorHandler.getErrorMessage(e);
        }

        ErrorHandler.showErrorSnackBar(context, errorMessage);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: LoadingOverlay(
        isLoading: _isLoading,
        message: 'Updating profile...',
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: screenWidth - 48, // Account for dialog margins
          ),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(20), // Reduced from 24
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Edit Profile',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? AppTheme.textPrimaryDark
                            : AppTheme.textPrimaryLight,
                      ),
                    ),
                    const SizedBox(height: 20),
                    _buildAvatarPicker(theme),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _usernameController,
                      decoration: const InputDecoration(
                        labelText: 'Username',
                        prefixIcon: Icon(Icons.person_outlined),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                      ),
                      validator: Validators.validateUsername,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _saveChanges(),
                      enabled: !_isLoading,
                    ),
                    const SizedBox(height: 20),
                    _buildActionButtons(theme),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAvatarPicker(ThemeData theme) {
    return Center(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          GestureDetector(
            onTap: _isLoading ? null : _pickAvatar,
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
                radius: 50, // Fixed size instead of ProfileConstants
                backgroundColor: theme.colorScheme.primary.withValues(
                  alpha: .1,
                ),
                backgroundImage: _getAvatarImage(),
                child: _getAvatarPlaceholder(theme),
              ),
            ),
          ),
          if (_newAvatar != null)
            Positioned(
              top: -5,
              right: -5,
              child: GestureDetector(
                onTap: _isLoading ? null : _removeAvatar,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.error,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: .2),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 16),
                ),
              ),
            ),
          Positioned(
            bottom: 0,
            right: 0,
            child: GestureDetector(
              onTap: _isLoading ? null : _pickAvatar,
              child: Container(
                padding: const EdgeInsets.all(8),
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
                  size: 18,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  ImageProvider? _getAvatarImage() {
    if (_newAvatar != null) {
      return FileImage(_newAvatar!) as ImageProvider;
    } else if (widget.user.avatarUrl != null) {
      return CachedNetworkImageProvider(widget.user.avatarUrl!) as ImageProvider;
    }
    return null;
  }

  Widget? _getAvatarPlaceholder(ThemeData theme) {
    if (_newAvatar == null && widget.user.avatarUrl == null) {
      return Icon(
        Icons.person_outlined,
        size: 50,
        color: theme.colorScheme.primary,
      );
    }
    return null;
  }

  Widget _buildActionButtons(ThemeData theme) {
    return SizedBox(
      width: double.infinity,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Flexible(
            child: TextButton(
              onPressed: _isLoading
                  ? null
                  : () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: ElevatedButton(
              onPressed: _isLoading ? null : _saveChanges,
              child: const Text('Save'),
            ),
          ),
        ],
      ),
    );
  }
}

// Custom Exception Classes
class NetworkException implements Exception {
  final String message;
  NetworkException(this.message);

  @override
  String toString() => 'NetworkException: $message';
}

class ValidationException implements Exception {
  final String message;
  ValidationException(this.message);

  @override
  String toString() => 'ValidationException: $message';
}
