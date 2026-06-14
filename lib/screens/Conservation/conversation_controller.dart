import 'dart:io';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';

import 'package:new_chart/core/error_handler.dart';
import 'package:new_chart/providers/chart_provider.dart';
import 'package:new_chart/repositories/user_repository.dart';
import 'package:new_chart/services/image_service.dart';
import 'package:new_chart/services/message_service.dart';

import 'package:new_chart/services/notification_services.dart';
import 'package:new_chart/services/zego_services.dart';
import 'package:zego_uikit_prebuilt_call/zego_uikit_prebuilt_call.dart';
import '../../models/user_model.dart';
import '../../models/message_model.dart';
import '../../providers/auth_provider.dart';

import '../../core/cloudinary_config.dart';
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
  StorageRepository get _storageRepo => ref.read(storageRepositoryProvider);
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

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

  // Send text message with notification
  Future<void> sendTextMessage({
    required String content,
    String? replyToMessageId,
    String? replyToContent,
    String? replyToSenderId,
  }) async {
    try {
      final currentUser = ref.read(currentUserProvider).value;
      if (currentUser == null) return;

      // Send message to Firestore
      await _chatService.sendMessage(
        chatId: chatId,
        receiverId: friend.uid,
        content: content,
        type: MessageType.text,
        replyToMessageId: replyToMessageId,
        replyToContent: replyToContent,
        replyToSenderId: replyToSenderId,
      );

      // Send push notification
      await _sendPushNotification(
        receiverId: friend.uid,
        senderName: currentUser.username,
        messageContent: content,
        senderId: currentUser.uid,
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
    try {
      return await ImagePickerService.pickImageFromGallery();
    } catch (e) {
      if (context.mounted) {
        ErrorHandler.showErrorSnackBar(
          context,
          'Failed to select image: ${ErrorHandler.getErrorMessage(e)}',
        );
      }
      return null;
    }
  }

  // Pick video from gallery
  Future<File?> pickVideoFromGallery() async {
    try {
      debugPrint('Starting video picker...');
      final video = await ImagePickerService.pickVideoFromGallery();

      if (video != null) {
        final fileSize = await video.length();
        debugPrint('Video picked successfully: ${video.path}');
        debugPrint('Video size: ${fileSize / (1024 * 1024)} MB');
      } else {
        debugPrint('No video selected');
      }

      return video;
    } catch (e) {
      debugPrint('Error in pickVideoFromGallery: $e');
      if (context.mounted) {
        ErrorHandler.showErrorSnackBar(
          context,
          ErrorHandler.getErrorMessage(e),
        );
      }
      return null;
    }
  }

  // Pick video from camera
  Future<File?> pickVideoFromCamera() async {
    try {
      debugPrint('Starting video camera...');
      final video = await ImagePickerService.pickVideoFromCamera();

      if (video != null) {
        final fileSize = await video.length();
        debugPrint('Video recorded successfully: ${video.path}');
        debugPrint('Video size: ${fileSize / (1024 * 1024)} MB');
      } else {
        debugPrint('No video recorded');
      }

      return video;
    } catch (e) {
      debugPrint('Error in pickVideoFromCamera: $e');
      if (context.mounted) {
        ErrorHandler.showErrorSnackBar(
          context,
          ErrorHandler.getErrorMessage(e),
        );
      }
      return null;
    }
  }

  // Pick document
  Future<File?> pickDocument() async {
    try {
      final result = await FilePicker.platform.pickFiles();
      if (result != null && result.files.single.path != null) {
        return File(result.files.single.path!);
      }
      return null;
    } catch (e) {
      if (context.mounted) {
        ErrorHandler.showErrorSnackBar(
          context,
          'Failed to select document: ${ErrorHandler.getErrorMessage(e)}',
        );
      }
      return null;
    }
  }

  // Send voice message with notification
  Future<void> sendVoiceMessage(String audioPath, Duration duration) async {
    final file = File(audioPath);
    try {
      final currentUser = ref.read(currentUserProvider).value;
      if (currentUser == null) return;

      if (kDebugMode) debugPrint('Uploading voice message...');

      final audioUrl = await _storageRepo.uploadChatMedia(
        chatId: chatId,
        file: file,
        fileType: 'voice',
      );

      if (kDebugMode) debugPrint('Voice uploaded: $audioUrl');

      await _chatService.sendMessage(
        chatId: chatId,
        receiverId: friend.uid,
        content: 'Voice message',
        type: MessageType.voice,
        mediaUrl: audioUrl,
        fileName: '${duration.inSeconds}s',
      );

      // Send push notification
      await _sendPushNotification(
        receiverId: friend.uid,
        senderName: currentUser.username,
        messageContent: '🎤 Voice message',
        senderId: currentUser.uid,
      );

      if (context.mounted) {
        ErrorHandler.showSuccessSnackBar(context, 'Voice message sent');
      }
    } catch (e) {
      debugPrint('Error sending voice message: $e');
      if (context.mounted) {
        ErrorHandler.showErrorSnackBar(
          context,
          ErrorHandler.getErrorMessage(e),
        );
      }
      rethrow;
    } finally {
      // Always clean up the temp file — even if upload or Firestore write failed.
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {
        // Ignore cleanup errors; they're non-fatal.
      }
    }
  }

  // Send media message with notification
  Future<void> sendMediaMessage(MessageType type, File file) async {
    try {
      final currentUser = ref.read(currentUserProvider).value;
      if (currentUser == null) return;

      if (kDebugMode) {
        debugPrint('Starting to send ${type.name} message...');
        debugPrint('File path: ${file.path}');
        debugPrint('File exists: ${await file.exists()}');
        final fileSize = await file.length();
        debugPrint('File size: ${fileSize / (1024 * 1024)} MB');
      }

      if (kDebugMode) debugPrint('Uploading ${type.name} to Cloudinary...');
      final mediaUrl = await _storageRepo.uploadChatMedia(
        chatId: chatId,
        file: file,
        fileType: type.toString().split('.').last,
      );

      if (kDebugMode) debugPrint('${type.name} uploaded successfully: $mediaUrl');

      final content = type == MessageType.image
          ? 'Image'
          : type == MessageType.video
          ? 'Video'
          : 'File';

      await _chatService.sendMessage(
        chatId: chatId,
        receiverId: friend.uid,
        content: content,
        type: type,
        mediaUrl: mediaUrl,
        fileName: file.path.split('/').last,
      );

      debugPrint('${type.name} message sent successfully');

      // Send push notification with appropriate emoji
      final notificationContent = type == MessageType.image
          ? '📷 Photo'
          : type == MessageType.video
          ? '🎥 Video'
          : '📎 File';

      await _sendPushNotification(
        receiverId: friend.uid,
        senderName: currentUser.username,
        messageContent: notificationContent,
        senderId: currentUser.uid,
      );

      if (context.mounted) {
        ErrorHandler.showSuccessSnackBar(
          context,
          '${type.name.capitalize()} sent successfully',
        );
      }
    } catch (e) {
      debugPrint('Error sending ${type.name} message: $e');
      debugPrint('Error stack trace: ${StackTrace.current}');
      if (context.mounted) {
        ErrorHandler.showErrorSnackBar(
          context,
          'Failed to send ${type.name}: ${ErrorHandler.getErrorMessage(e)}',
        );
      }
      rethrow;
    }
  }

  // Private method to send push notification
  Future<void> _sendPushNotification({
    required String receiverId,
    required String senderName,
    required String messageContent,
    required String senderId,
  }) async {
    try {
      // Get receiver's data from Firestore
      final receiverDoc = await _firestore
          .collection('users')
          .doc(receiverId)
          .get();

      if (!receiverDoc.exists) {
        debugPrint('❌ Receiver not found in Firestore');
        return;
      }

      final receiverData = receiverDoc.data();
      if (receiverData == null) {
        debugPrint('❌ Receiver data is null');
        return;
      }

      final receiverToken = receiverData['fcmToken'] as String?;

      if (receiverToken == null || receiverToken.isEmpty) {
        debugPrint('❌ Receiver has no FCM token');
        return;
      }

      debugPrint(
        '📱 Receiver token found: ${receiverToken.substring(0, 20)}...',
      );

      // Check if receiver is online and currently in this chat
      final isReceiverOnline = receiverData['isOnline'] == true;
      final isReceiverTyping = receiverData['isTyping'] == true;
      final receiverChatId = receiverData['typingInChatId'] as String?;

      final isReceiverInThisChat = isReceiverOnline && receiverChatId == chatId;

      // Only send notification if receiver is not currently in this chat
      if (!isReceiverInThisChat) {
        debugPrint('📤 Sending push notification...');

        final success = await NotificationService.sendMessageNotification(
          receiverToken: receiverToken,
          senderName: senderName,
          messageContent: messageContent,
          chatId: chatId,
          senderId: senderId,
        );

        if (success) {
          debugPrint('✅ Push notification sent successfully');
        } else {
          debugPrint('❌ Failed to send push notification');
        }
      } else {
        debugPrint('⏭️ Skipping notification - receiver is in chat');
        debugPrint('   - isOnline: $isReceiverOnline');
        debugPrint('   - isTyping: $isReceiverTyping');
        debugPrint('   - inChatId: $receiverChatId');
      }
    } catch (e) {
      debugPrint('❌ Error sending push notification: $e');
      // Don't throw - notification failure shouldn't stop message sending
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
  bool isUserBlocked(String currentUserId) {
    final currentUser = ref.read(currentUserProvider).value;
    return currentUser?.blockedUsers.contains(friend.uid) ?? false;
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
        // These appear in the ZEGOCLOUD UI overlay on the callee side
        notificationTitle: currentUser.username,
        notificationMessage: '${currentUser.username} is calling you...',
      );
      debugPrint('📞 Audio call sent to: ${friend.username} (${friend.uid})');
    } catch (e) {
      debugPrint('❌ Audio call error: $e');
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
        // These appear in the ZEGOCLOUD UI overlay on the callee side
        notificationTitle: currentUser.username,
        notificationMessage: '${currentUser.username} is video calling you...',
      );
      debugPrint('🎥 Video call sent to: ${friend.username} (${friend.uid})');
    } catch (e) {
      debugPrint('❌ Video call error: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to start video call')),
        );
      }
    }
  }
}

// Extension helper for string capitalization
extension StringExtension on String {
  String capitalize() {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1)}';
  }
}
