import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:uuid/uuid.dart';
import 'package:vibetalk/models/chart_model.dart';
import 'package:vibetalk/services/message_service.dart';
import '../models/message_model.dart';
import '../models/user_model.dart';
import 'auth_provider.dart';

final chatListProvider = StreamProvider<List<ChatModel>>((ref) async* {
  final currentUser = ref.watch(currentUserProvider).value;
  if (currentUser == null) {
    yield [];
    return;
  }

  try {
    await for (final snapshot
        in FirebaseFirestore.instance
            .collection('chats')
            .where('participants', arrayContains: currentUser.uid)
            .orderBy('lastMessageTime', descending: true)
            .snapshots()) {
      // Check if user is still authenticated
      final stillAuthenticated = ref.read(currentUserProvider).value;
      if (stillAuthenticated == null) {
        yield [];
        return;
      }

      final chats = snapshot.docs
          .map((doc) {
            try {
              return ChatModel.fromMap(doc.data());
            } catch (e) {
              return null;
            }
          })
          .whereType<ChatModel>()
          .toList();

      yield chats;
    }
  } catch (e) {
    // Handle permission errors gracefully (e.g., after logout)
    yield [];
  }
});

class MessagesPagination {
  final String chatId;
  final int limit;
  final DocumentSnapshot? lastDocument;

  MessagesPagination({
    required this.chatId,
    this.limit = 20,
    this.lastDocument,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MessagesPagination &&
          runtimeType == other.runtimeType &&
          chatId == other.chatId &&
          limit == other.limit &&
          lastDocument == other.lastDocument;

  @override
  int get hashCode => chatId.hashCode ^ limit.hashCode ^ lastDocument.hashCode;
}

final messagesProvider = StreamProvider.family<List<MessageModel>, String>((
  ref,
  chatId,
) async* {
  final currentUser = ref.watch(currentUserProvider).value;
  if (currentUser == null) {
    yield [];
    return;
  }

  // Read blocked list once — filter locally with zero extra Firestore reads
  final blockedIds = Set<String>.from(currentUser.blockedUsers);

  try {
    await for (final snapshot
        in FirebaseFirestore.instance
            .collection('chats')
            .doc(chatId)
            .collection('messages')
            .orderBy('timestamp', descending: true)
            .limit(
              50,
            ) // Prevents ANR on low-end devices — pagination can be added later
            .snapshots()) {
      final stillAuthenticated = ref.read(currentUserProvider).value;
      if (stillAuthenticated == null) {
        yield [];
        return;
      }

      yield snapshot.docs
          .map((doc) {
            try {
              return MessageModel.fromMap(doc.data());
            } catch (e) {
              return null;
            }
          })
          .whereType<MessageModel>()
          .where((m) => !blockedIds.contains(m.senderId))
          .toList();
    }
  } catch (e) {
    yield [];
  }
});

final messageServiceProvider = Provider<MessageService>((ref) {
  return MessageService();
});

final chatServiceProvider = Provider((ref) => ChatService(ref));

class ChatService {
  final Ref ref;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Uuid _uuid = const Uuid();

  ChatService(this.ref);

  Future<void> sendMessage({
    required String chatId,
    required String receiverId,
    required String content,
    required MessageType type,
    String? mediaUrl,
    String? fileName,
    String? replyToMessageId,
    String? replyToContent,
    String? replyToSenderId,
  }) async {
    try {
      final currentUser = ref.read(currentUserProvider).value;
      if (currentUser == null) throw Exception('Not authenticated');

      final userRepository = ref.read(userRepositoryProvider);
      final isBlockedByReceiver = await userRepository.isUserBlocked(
        receiverId,
        currentUser.uid,
      );

      if (isBlockedByReceiver) {
        throw Exception(
          'Cannot send message. You have been blocked by this user.',
        );
      }

      final hasBlockedReceiver = currentUser.blockedUsers.contains(receiverId);

      if (hasBlockedReceiver) {
        throw Exception('Cannot send message to a blocked user.');
      }

      final messageId = _uuid.v4();
      // Use client time only for the local MessageModel object (optimistic UI).
      // The actual Firestore document uses FieldValue.serverTimestamp() so
      // ordering is always based on the server clock — not device clocks.
      final clientNow = DateTime.now();
      final message = MessageModel(
        messageId: messageId,
        senderId: currentUser.uid,
        receiverId: receiverId,
        content: content,
        type: type,
        timestamp: clientNow,
        isRead: false,
        mediaUrl: mediaUrl,
        replyToMessageId: replyToMessageId,
        replyToContent: replyToContent,
        replyToSenderId: replyToSenderId,
      );

      final batch = _firestore.batch();

      final messageRef = _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .doc(messageId);

      // Write to Firestore with SERVER timestamp for correct ordering.
      final messageData = message.toMap()
        ..['timestamp'] = FieldValue.serverTimestamp();
      batch.set(messageRef, messageData);

      final chatRef = _firestore.collection('chats').doc(chatId);
      batch.update(chatRef, {
        'lastMessage': _getLastMessagePreview(type, content),
        // Use server timestamp for the chat's last-message time too.
        'lastMessageTime': FieldValue.serverTimestamp(),
        'lastMessageType': type.toString().split('.').last,
        'lastMessageSenderId': currentUser.uid,
        'unreadCount.$receiverId': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await batch.commit();
      //   _sendNotificationAsync(receiverId, currentUser, type, content, chatId);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> markMessagesAsRead(String chatId, String currentUserId) async {
    try {
      final messages = await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .where('receiverId', isEqualTo: currentUserId)
          .where('isRead', isEqualTo: false)
          .limit(50)
          .get();

      if (messages.docs.isEmpty) {
        await _firestore.collection('chats').doc(chatId).update({
          'unreadCount.$currentUserId': 0,
        });
        return;
      }

      final batch = _firestore.batch();

      batch.update(_firestore.collection('chats').doc(chatId), {
        'unreadCount.$currentUserId': 0,
      });

      for (var doc in messages.docs) {
        batch.update(doc.reference, {'isRead': true});
      }

      await batch.commit();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> clearConversation(String chatId) async {
    try {
      // Delete all messages in batches of 500 until the collection is empty.
      // A single .limit(500) batch silently leaves data behind in large chats.
      while (true) {
        final messages = await _firestore
            .collection('chats')
            .doc(chatId)
            .collection('messages')
            .limit(500)
            .get();

        if (messages.docs.isEmpty) break;

        final batch = _firestore.batch();
        for (var doc in messages.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      }

      await _firestore.collection('chats').doc(chatId).update({
        'lastMessage': null,
        'lastMessageTime': null,
        'lastMessageType': null,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      rethrow;
    }
  }

  Future<String> getOrCreateChat(String otherUserId) async {
    try {
      final currentUser = ref.read(currentUserProvider).value;
      if (currentUser == null) throw Exception('Not authenticated');

      final userRepository = ref.read(userRepositoryProvider);

      final isBlocked = currentUser.blockedUsers.contains(otherUserId);

      final isBlockedBy = await userRepository.isUserBlocked(
        otherUserId,
        currentUser.uid,
      );

      if (isBlocked) {
        throw Exception('Cannot create chat with a blocked user.');
      }

      if (isBlockedBy) {
        throw Exception(
          'Cannot create chat. You have been blocked by this user.',
        );
      }

      final chatId = generateChatId(currentUser.uid, otherUserId);

      final chatDoc = await _firestore.collection('chats').doc(chatId).get();

      if (!chatDoc.exists) {
        final otherUserDoc = await _firestore
            .collection('users')
            .doc(otherUserId)
            .get();

        if (!otherUserDoc.exists) {
          throw Exception('User not found');
        }

        final otherUser = UserModel.fromMap(otherUserDoc.data()!);

        await _firestore.collection('chats').doc(chatId).set({
          'chatId': chatId,
          'participants': [currentUser.uid, otherUserId],
          'participantsData': {
            currentUser.uid: {
              'username': currentUser.username,
              'avatarUrl': currentUser.avatarUrl,
            },
            otherUserId: {
              'username': otherUser.username,
              'avatarUrl': otherUser.avatarUrl,
            },
          },
          'lastMessage': null,
          'lastMessageTime': null,
          'lastMessageType': null,
          'lastMessageSenderId': null,
          'unreadCount': {currentUser.uid: 0, otherUserId: 0},
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      return chatId;
    } catch (e) {
      rethrow;
    }
  }

  String _getLastMessagePreview(MessageType type, String content) {
    switch (type) {
      case MessageType.text:
        return content.length > 50 ? '${content.substring(0, 50)}...' : content;
      case MessageType.image:
        return '📷 Image';
      case MessageType.video:
        return '🎥 Video';
      case MessageType.voice:
        return '🎵 Audio';
      case MessageType.file:
        return '📎 File';
    }
  }

  String generateChatId(String uid1, String uid2) {
    return uid1.hashCode <= uid2.hashCode ? '${uid1}_$uid2' : '${uid2}_$uid1';
  }
}
