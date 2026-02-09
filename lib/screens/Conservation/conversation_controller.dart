import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:new_chart/core/env_config.dart';
import 'package:new_chart/core/error_handler.dart';
import 'package:new_chart/providers/chart_provider.dart';
import 'package:new_chart/repositories/user_repository.dart';
import 'package:new_chart/services/image_service.dart';
import 'package:new_chart/services/message_service.dart';
import 'package:new_chart/services/zego_services.dart';
import 'package:zego_uikit_prebuilt_call/zego_uikit_prebuilt_call.dart';
import '../../models/user_model.dart';
import '../../models/message_model.dart';
import '../../providers/auth_provider.dart' hide userRepositoryProvider;
import '../../providers/user_provider.dart';
import '../../repositories/storage_repository.dart';

class ConversationController {
  final WidgetRef ref;
  final BuildContext context;
  final String chatId;
  final UserModel friend;

  ConversationController({
    required this.ref,
    required this.context,
    required this.chatId,
    required this.friend,
  });
  UserRepository get _userRepository => ref.read(userRepositoryProvider);
  ChatService get _chatService => ref.read(chatServiceProvider);
  MessageService get _messageService => ref.read(messageServiceProvider);
  Future<void> markMessagesAsRead() async {
    final currentUser = ref.read(currentUserProvider).value;
    if (currentUser != null) {
      await _chatService.markMessagesAsRead(chatId, currentUser.uid);
    }
  }

  Future<void> updateTypingStatus({
    required String userId,
    required bool isTyping,
  }) async {
    await _userRepository.updateTypingStatus(
      userId: userId,
      isTyping: isTyping,
      chatId: isTyping ? chatId : null,
    );
  }

  // Send text message
  Future<void> sendTextMessage({
    required String content,
    String? replyToMessageId,
    String? replyToContent,
    String? replyToSenderId,
  }) async {
    try {
      await _chatService.sendMessage(
        chatId: chatId,
        receiverId: friend.uid,
        content: content,
        type: MessageType.text,
        replyToMessageId: replyToMessageId,
        replyToContent: replyToContent,
        replyToSenderId: replyToSenderId,
      );
    } catch (e) {
      if (context.mounted) {
        ErrorHandler.showErrorSnackBar(
          context,
          ErrorHandler.getErrorMessage(e),
        );
      }
      rethrow;
    }
  }

  // Add reaction to message
  Future<void> addReaction(String messageId, String emoji) async {
    final currentUser = ref.read(currentUserProvider).value;
    if (currentUser == null) return;

    try {
      await _messageService.addReaction(
        chatId,
        messageId,
        emoji,
        currentUser.uid,
      );
    } catch (e) {
      if (context.mounted) {
        ErrorHandler.showErrorSnackBar(
          context,
          ErrorHandler.getErrorMessage(e),
        );
      }
    }
  }

  // Edit message
  Future<void> editMessage(String messageId, String newContent) async {
    try {
      await _messageService.editMessage(chatId, messageId, newContent);
      if (context.mounted) {
        ErrorHandler.showSuccessSnackBar(context, 'Message edited');
      }
    } catch (e) {
      if (context.mounted) {
        ErrorHandler.showErrorSnackBar(
          context,
          ErrorHandler.getErrorMessage(e),
        );
      }
    }
  }

  // Delete message
  Future<bool> deleteMessage(String messageId) async {
    if (!context.mounted) return false;

    final confirm = await ErrorHandler.showConfirmDialog(
      context,
      'Delete Message',
      'Are you sure you want to delete this message?',
    );

    if (!confirm) return false;

    try {
      await _messageService.deleteMessage(chatId, messageId);
      if (context.mounted) {
        ErrorHandler.showSuccessSnackBar(context, 'Message deleted');
      }
      return true;
    } catch (e) {
      if (context.mounted) {
        ErrorHandler.showErrorSnackBar(
          context,
          ErrorHandler.getErrorMessage(e),
        );
      }
      return false;
    }
  }

  // Copy to clipboard
  void copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ErrorHandler.showSuccessSnackBar(context, 'Copied to clipboard');
    }
  }

  // Capture photo from camera
  Future<File?> capturePhoto() async {
    try {
      return await ImagePickerService.pickImageFromCamera();
    } catch (e) {
      if (context.mounted) {
        ErrorHandler.showErrorSnackBar(
          context,
          'Failed to capture photo: ${ErrorHandler.getErrorMessage(e)}',
        );
      }
      return null;
    }
  }

  // Pick image from gallery
  Future<File?> pickImageFromGallery() async {
    return await ImagePickerService.pickImageFromGallery();
  }

  // Pick video from gallery
  Future<File?> pickVideoFromGallery() async {
    return await ImagePickerService.pickVideoFromGallery();
  }

  // Pick document
  Future<File?> pickDocument() async {
    final result = await FilePicker.platform.pickFiles();
    if (result != null && result.files.single.path != null) {
      return File(result.files.single.path!);
    }
    return null;
  }

  // Send voice message
  Future<void> sendVoiceMessage(String audioPath, Duration duration) async {
    try {
      final storageRepo = StorageRepository(
        cloudName: EnvConfig.cloudinaryCloudName,
        uploadPreset: EnvConfig.cloudinaryUploadPreset,
      );

      final file = File(audioPath);
      final audioUrl = await storageRepo.uploadChatMedia(
        chatId: chatId,
        file: file,
        fileType: 'voice',
      );

      await _chatService.sendMessage(
        chatId: chatId,
        receiverId: friend.uid,
        content: 'Voice message',
        type: MessageType.voice,
        mediaUrl: audioUrl,
        fileName: '${duration.inSeconds}s',
      );

      if (await file.exists()) {
        await file.delete();
      }

      if (context.mounted) {
        ErrorHandler.showSuccessSnackBar(context, 'Voice message sent');
      }
    } catch (e) {
      if (context.mounted) {
        ErrorHandler.showErrorSnackBar(
          context,
          ErrorHandler.getErrorMessage(e),
        );
      }
      rethrow;
    }
  }

  // Send media message
  Future<void> sendMediaMessage(MessageType type, File file) async {
    try {
      final storageRepo = StorageRepository(
        cloudName: EnvConfig.cloudinaryCloudName,
        uploadPreset: EnvConfig.cloudinaryUploadPreset,
      );

      final mediaUrl = await storageRepo.uploadChatMedia(
        chatId: chatId,
        file: file,
        fileType: type.toString().split('.').last,
      );

      await _chatService.sendMessage(
        chatId: chatId,
        receiverId: friend.uid,
        content: type == MessageType.image
            ? 'Image'
            : type == MessageType.video
            ? 'Video'
            : 'File',
        type: type,
        mediaUrl: mediaUrl,
        fileName: file.path.split('/').last,
      );

      if (context.mounted) {
        ErrorHandler.showSuccessSnackBar(context, 'Sent successfully');
      }
    } catch (e) {
      if (context.mounted) {
        ErrorHandler.showErrorSnackBar(
          context,
          ErrorHandler.getErrorMessage(e),
        );
      }
      rethrow;
    }
  }

  // Clear conversation
  Future<void> clearConversation() async {
    if (!context.mounted) return;

    final confirm = await ErrorHandler.showConfirmDialog(
      context,
      'Clear Conversation',
      'Are you sure you want to clear all messages? This action cannot be undone.',
    );

    if (!confirm) return;

    try {
      await _chatService.clearConversation(chatId);
      if (context.mounted) {
        ErrorHandler.showSuccessSnackBar(context, 'Conversation cleared');
      }
    } catch (e) {
      if (context.mounted) {
        ErrorHandler.showErrorSnackBar(
          context,
          ErrorHandler.getErrorMessage(e),
        );
      }
    }
  }

  // Check if user is blocked
  Future<bool> isUserBlocked(String currentUserId) async {
    return await _userRepository.isUserBlocked(currentUserId, friend.uid);
  }

  // Block user
  Future<void> blockUser(String currentUserId) async {
    if (!context.mounted) return;

    final confirm = await ErrorHandler.showConfirmDialog(
      context,
      'Block ${friend.username}?',
      'You will no longer receive messages from this user.',
    );

    if (!confirm) return;

    try {
      await _userRepository.blockUser(currentUserId, friend.uid);
      if (context.mounted) {
        ErrorHandler.showSuccessSnackBar(context, '${friend.username} blocked');
        Navigator.pop(context);
      }
    } catch (e) {
      if (context.mounted) {
        ErrorHandler.showErrorSnackBar(
          context,
          ErrorHandler.getErrorMessage(e),
        );
      }
    }
  }

  // Unblock user
  Future<void> unblockUser(String currentUserId) async {
    try {
      await _userRepository.unblockUser(currentUserId, friend.uid);
      if (context.mounted) {
        ErrorHandler.showSuccessSnackBar(
          context,
          '${friend.username} unblocked',
        );
      }
    } catch (e) {
      if (context.mounted) {
        ErrorHandler.showErrorSnackBar(
          context,
          ErrorHandler.getErrorMessage(e),
        );
      }
    }
  }

  // Make audio call
  Future<void> makeAudioCall() async {
    final currentUser = ref.read(currentUserProvider).value;
    if (currentUser == null) return;

    if (!ZegoService.isInitialized) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Call service not ready yet')),
        );
      }
      return;
    }

    final callID = '${chatId}_${DateTime.now().millisecondsSinceEpoch}';

    try {
      await ZegoUIKitPrebuiltCallInvitationService().send(
        invitees: [ZegoCallUser(friend.uid, friend.username)],
        isVideoCall: false,
        resourceID: "zego_call",
        callID: callID,
        notificationTitle: 'Incoming call',
        notificationMessage: '${currentUser.username} is calling you...',
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Failed to start call')));
      }
    }
  }

  // Make video call
  Future<void> makeVideoCall() async {
    final currentUser = ref.read(currentUserProvider).value;
    if (currentUser == null) return;

    if (!ZegoService.isInitialized) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Call service not ready yet')),
        );
      }
      return;
    }

    final callID = '${chatId}_${DateTime.now().millisecondsSinceEpoch}';

    try {
      await ZegoUIKitPrebuiltCallInvitationService().send(
        invitees: [ZegoCallUser(friend.uid, friend.username)],
        isVideoCall: true,
        resourceID: "zego_call",
        callID: callID,
        notificationTitle: 'Incoming video call',
        notificationMessage: '${currentUser.username} is video calling you...',
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to start video call')),
        );
      }
    }
  }
}
