import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';

class UserRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Stream<UserModel?> getUserStream(String uid) {
    return _firestore.collection('users').doc(uid).snapshots().map((doc) {
      if (doc.exists && doc.data() != null) {
        try {
          // FIX: Always inject doc.id as 'uid'.
          // The Firestore document ID IS the Firebase Auth uid (guaranteed).
          // If the 'uid' field inside the document data is empty or missing
          // (a data creation bug), ZegoService.init() received an empty userId
          // and Zego silently rejected the call with "user parameters is not valid".
          final data = Map<String, dynamic>.from(doc.data()!);
          data['uid'] = doc.id;
          final userModel = UserModel.fromMap(data);

          // FIX: Guard against partial Firestore snapshots.
          // On every fresh install (uninstall + reinstall), signInWithEmailAndPassword
          // calls set({isOnline, fcmToken, lastSeen}, merge: true) AFTER Firebase Auth
          // fires authStateChanges. The Firestore listener is already active at that
          // point, so the merge write triggers a LOCAL optimistic snapshot containing
          // only those 3 fields — username and email are null because local cache was
          // wiped on uninstall. This caused:
          //   1. Zego init with empty userName → _pageManager null → call crash
          //   2. Profile screen flicker with blank Username/Email cards
          // Returning null here makes currentUserProvider yield null, which keeps
          // auth_wrapper on SplashScreen until the full server document arrives.
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
      await _firestore.collection('users').doc(uid).update({
        'avatarUrl': avatarUrl,
      });
    } catch (e) {
      rethrow;
    }
  }
}
