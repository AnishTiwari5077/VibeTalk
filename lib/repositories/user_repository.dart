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
        'typingInChatId': chatId,
      });
    } catch (e) {
      // Handle error silently
    }
  }

  Future<void> updateUserStatus({
    required String userId,
    required bool isOnline,
  }) async {
    try {
      await _firestore.collection('users').doc(userId).update({
        'isOnline': isOnline,
        'lastSeen': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (e) {
      throw Exception('Failed to update status: $e');
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

  /// Check both block directions in parallel.
  /// Returns (iBlockedThem, theyBlockedMe).
  Future<(bool, bool)> checkBlockStatus(
    String currentUserId,
    String otherUserId,
  ) async {
    try {
      final results = await Future.wait([
        _firestore.collection('users').doc(currentUserId).get(),
        _firestore.collection('users').doc(otherUserId).get(),
      ]);

      final myData = results[0].data();
      final theirData = results[1].data();

      final iBlockedThem =
          myData != null &&
          List<String>.from(myData['blockedUsers'] ?? []).contains(otherUserId);

      final theyBlockedMe =
          theirData != null &&
          List<String>.from(theirData['blockedUsers'] ?? []).contains(
            currentUserId,
          );

      return (iBlockedThem, theyBlockedMe);
    } catch (e) {
      return (false, false);
    }
  }

  Future<bool> isUserBlocked(String currentUserId, String otherUserId) async {
    final (iBlockedThem, _) = await checkBlockStatus(currentUserId, otherUserId);
    return iBlockedThem;
  }

  Future<bool> isBlockedByUser(String currentUserId, String otherUserId) async {
    final (_, theyBlockedMe) = await checkBlockStatus(currentUserId, otherUserId);
    return theyBlockedMe;
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
