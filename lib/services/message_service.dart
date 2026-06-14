// lib/services/message_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/message_model.dart';

class MessageService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> addReaction(
    String chatId,
    String messageId,
    String emoji,
    String userId,
  ) async {
    final messageRef = _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc(messageId);

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(messageRef);
      final data = snapshot.data();

      if (data == null) return;

      Map<String, dynamic> reactionsMap = Map<String, dynamic>.from(
        data['reactions'] ?? {},
      );

      Map<String, List<String>> reactions = {};
      reactionsMap.forEach((key, value) {
        reactions[key] = List<String>.from(value);
      });

      String? userPreviousEmoji;
      reactions.forEach((existingEmoji, users) {
        if (users.contains(userId)) {
          userPreviousEmoji = existingEmoji;
        }
      });

      if (userPreviousEmoji != null) {
        reactions[userPreviousEmoji]!.remove(userId);
        if (reactions[userPreviousEmoji]!.isEmpty) {
          reactions.remove(userPreviousEmoji);
        }
      }

      if (userPreviousEmoji != emoji) {
        if (reactions.containsKey(emoji)) {
          reactions[emoji]!.add(userId);
        } else {
          reactions[emoji] = [userId];
        }
      }

      transaction.update(messageRef, {'reactions': reactions});
    });
  }

  Future<void> editMessage(
    String chatId,
    String messageId,
    String newContent,
  ) async {
    await _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc(messageId)
        .update({
          'content': newContent,
          'isEdited': true,
          'editedAt': DateTime.now().millisecondsSinceEpoch,
        });
  }

  // Delete message
  Future<void> deleteMessage(String chatId, String messageId) async {
    await _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc(messageId)
        .delete();
  }

  Future<MessageModel?> getMessageById(String chatId, String messageId) async {
    final doc = await _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc(messageId)
        .get();

    if (!doc.exists) return null;
    return MessageModel.fromMap(doc.data()!);
  }
}
