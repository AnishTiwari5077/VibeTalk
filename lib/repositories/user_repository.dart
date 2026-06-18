import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';

class UserRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Stream<UserModel?> getUserStream(String uid) {
    return _firestore.collection('users').doc(uid).snapshots().map((doc) {
      if (doc.exists && doc.data() != null) {
        try {
          // Always inject the Firestore document ID as 'uid'.
          // The doc ID IS the Firebase Auth uid (guaranteed by auth_repository).
          // The 'uid' field inside the document may be empty on a partial
          // Firestore snapshot (e.g., fresh install merge-write triggers a
          // local optimistic snapshot with only 3 fields before the full
          // server document arrives). Using doc.id avoids that stale state.
          final data = Map<String, dynamic>.from(doc.data()!);
          data['uid'] = doc.id;
          final userModel = UserModel.fromMap(data);

          // Guard against partial snapshots (username/email null):
          // Returning null keeps auth_wrapper on SplashScreen until the
          // full server document arrives with all required fields.
          if (userModel.username.isEmpty || userModel.email.isEmpty) {
            return null;
          }

          return userModel;
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
    final doc = await _firestore.collection('users').doc(uid).get();
    if (doc.exists && doc.data() != null) {
      final data = Map<String, dynamic>.from(doc.data()!);
      data['uid'] = doc.id; // FIX: always use authoritative doc id
      return UserModel.fromMap(data);
    }
    return null;
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
                  final data = Map<String, dynamic>.from(doc.data());
                  data['uid'] = doc.id; // FIX: always use authoritative doc id
                  return UserModel.fromMap(data);
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
                  final data = Map<String, dynamic>.from(doc.data());
                  data['uid'] = doc.id; // FIX: always use authoritative doc id
                  return UserModel.fromMap(data);
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
    await _firestore.collection('users').doc(uid).update(data);
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
      // 1. Update the user document.
      await _firestore.collection('users').doc(uid).update({
        'avatarUrl': avatarUrl,
      });

      // 2. Propagate the new avatar to every chat where this user is a
      //    participant.  participantsData is cached in the chat document and
      //    is used by ChatListScreen for fast avatar display — without this
      //    update the chat list would show the old (or missing) avatar until
      //    the next time the chat is fully re-created.
      final chatsSnap = await _firestore
          .collection('chats')
          .where('participants', arrayContains: uid)
          .get();

      if (chatsSnap.docs.isNotEmpty) {
        final batch = _firestore.batch();
        for (final doc in chatsSnap.docs) {
          batch.update(doc.reference, {
            'participantsData.$uid.avatarUrl': avatarUrl,
          });
        }
        await batch.commit();
      }
    } catch (e) {
      rethrow;
    }
  }
}
