// lib/screens/conversation/widgets/message_options_sheet.dart

import 'package:flutter/material.dart';
import 'package:vibetalk/models/message_model.dart';
import 'package:vibetalk/theme/app_theme.dart';
import 'package:vibetalk/widgets/reaction_picker.dart';

class MessageOptionsSheet extends StatelessWidget {
  final MessageModel message;
  final bool isMyMessage;
  final Function(String emoji) onReactionSelected;
  final VoidCallback onReply;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback onCopy;

  const MessageOptionsSheet({
    super.key,
    required this.message,
    required this.isMyMessage,
    required this.onReactionSelected,
    required this.onReply,
    this.onEdit,
    this.onDelete,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: ReactionPicker(onReactionSelected: onReactionSelected),
            ),
            const Divider(height: 1),
            _buildOption(
              context,
              icon: Icons.reply_rounded,
              label: 'Reply',
              onTap: onReply,
            ),
            if (onEdit != null && message.type == MessageType.text)
              _buildOption(
                context,
                icon: Icons.edit_rounded,
                label: 'Edit',
                onTap: onEdit,
              ),
            if (message.type == MessageType.text)
              _buildOption(
                context,
                icon: Icons.copy_rounded,
                label: 'Copy',
                onTap: onCopy,
              ),
            if (onDelete != null)
              _buildOption(
                context,
                icon: Icons.delete_rounded,
                label: 'Delete',
                onTap: onDelete,
                isDestructive: true,
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildOption(
    BuildContext context, {
    required IconData icon,
    required String label,
    VoidCallback? onTap,
    bool isDestructive = false,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return ListTile(
      leading: Icon(
        icon,
        color: isDestructive
            ? theme.colorScheme.error
            : (isDark ? AppTheme.textPrimaryDark : AppTheme.textPrimaryLight),
      ),
      title: Text(
        label,
        style: TextStyle(
          color: isDestructive
              ? theme.colorScheme.error
              : (isDark ? AppTheme.textPrimaryDark : AppTheme.textPrimaryLight),
        ),
      ),
      onTap: onTap,
    );
  }
}
