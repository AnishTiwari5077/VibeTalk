import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';

class UserRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Stream<UserModel?> getUserStream(String uid) {
    return _firestore.collection('users').doc(uid).snapshots().map((doc) {
      if (doc.exists && doc.data() != null) {
        try {
          return UserModel.fromMap(doc.data()!);
        } catch (e) {
          return null;
        }
      }
      return null;
    });
  }

  Future<void> updateTypingStatus({
    required String userId,
    required bool isTyping,
    String? chatId,
  }) async {
    try {
      await _firestore.collection('users').doc(userId).update({
        'isTyping': isTyping,
        'typingInChatId': isTyping ? chatId : null,
      });
    } catch (e) {
      // Handle error silently
    }
  }

  Future<void> blockUser(String currentUserId, String userToBlockId) async {
    try {
      await _firestore.collection('users').doc(currentUserId).update({
        'blockedUsers': FieldValue.arrayUnion([userToBlockId]),
      });
    } catch (e) {
      throw Exception('Failed to block user: $e');
    }
  }

  Future<void> unblockUser(String currentUserId, String userToUnblockId) async {
    try {
      await _firestore.collection('users').doc(currentUserId).update({
        'blockedUsers': FieldValue.arrayRemove([userToUnblockId]),
      });
    } catch (e) {
      throw Exception('Failed to unblock user: $e');
    }
  }

  Future<bool> isUserBlocked(String currentUserId, String otherUserId) async {
    try {
      final userDoc = await _firestore
          .collection('users')
          .doc(currentUserId)
          .get();
      final userData = userDoc.data();
      if (userData == null) return false;

      final blockedUsers = List<String>.from(userData['blockedUsers'] ?? []);
      return blockedUsers.contains(otherUserId);
    } catch (e) {
      return false;
    }
  }

  Future<bool> isBlockedByUser(String currentUserId, String otherUserId) async {
    try {
      final userDoc = await _firestore
          .collection('users')
          .doc(otherUserId)
          .get();
      final userData = userDoc.data();
      if (userData == null) return false;

      final blockedUsers = List<String>.from(userData['blockedUsers'] ?? []);
      return blockedUsers.contains(currentUserId);
    } catch (e) {
      return false;
    }
  }

  Future<UserModel?> getUser(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists && doc.data() != null) {
        return UserModel.fromMap(doc.data()!);
      }
      return null;
    } catch (e) {
      rethrow;
    }
  }

  Stream<List<UserModel>> getAllUsers(String currentUserId) {
    return _firestore
        .collection('users')
        .where('uid', isNotEqualTo: currentUserId)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) {
                try {
                  return UserModel.fromMap(doc.data());
                } catch (e) {
                  return null;
                }
              })
              .whereType<UserModel>()
              .toList();
        });
  }

  Stream<List<UserModel>> searchUsers(String query, String currentUserId) {
    if (query.isEmpty) {
      return getAllUsers(currentUserId);
    }

    return _firestore
        .collection('users')
        .where('searchKeywords', arrayContains: query.toLowerCase())
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) {
                try {
                  return UserModel.fromMap(doc.data());
                } catch (e) {
                  return null;
                }
              })
              .whereType<UserModel>()
              .where((user) => user.uid != currentUserId)
              .toList();
        });
  }

  Future<void> updateUser(String uid, Map<String, dynamic> data) async {
    try {
      await _firestore.collection('users').doc(uid).update(data);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> updateUsername(String uid, String username) async {
    try {
      await _firestore.collection('users').doc(uid).update({
        'username': username,
        'searchKeywords': UserModel.generateSearchKeywords(username),
      });
    } catch (e) {
      rethrow;
    }
  }

  Future<void> updateAvatar(String uid, String avatarUrl) async {
    try {
      await _firestore.collection('users').doc(uid).update({
        'avatarUrl': avatarUrl,
      });
    } catch (e) {
      rethrow;
    }
  }
}
