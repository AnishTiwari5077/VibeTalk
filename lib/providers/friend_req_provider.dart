import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:vibetalk/services/notification_services.dart';
import 'package:uuid/uuid.dart';
import '../models/friend_request_model.dart';
import '../models/user_model.dart';
import 'auth_provider.dart';

final friendRequestProvider = Provider((ref) => FriendRequestService(ref));

class FriendRequestService {
  final Ref ref;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Uuid _uuid = const Uuid();

  FriendRequestService(this.ref);

  Future<void> sendFriendRequest(String receiverId) async {
    try {
      final currentUser = ref.read(currentUserProvider).value;
      if (currentUser == null) throw Exception('Not authenticated');

      final requestId = _uuid.v4();
      final friendRequest = FriendRequest(
        id: requestId,
        senderId: currentUser.uid,
        receiverId: receiverId,
        status: 'pending',
        timestamp: DateTime.now(),
      );

      await _firestore
          .collection('friendRequests')
          .doc(requestId)
          .set(friendRequest.toMap());

      final receiverDoc = await _firestore
          .collection('users')
          .doc(receiverId)
          .get();
      if (receiverDoc.exists) {
        final receiverData = UserModel.fromMap(receiverDoc.data()!);
        await NotificationService.sendFriendRequestNotification(
          receiverToken: receiverData.fcmToken,
          senderName: currentUser.username,
          senderId: currentUser.uid,
          requestId: requestId,
        );
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> acceptFriendRequest(String requestId, String senderId) async {
    try {
      final currentUser = ref.read(currentUserProvider).value;
      if (currentUser == null) throw Exception('Not authenticated');

      await _firestore.collection('friendRequests').doc(requestId).update({
        'status': 'accepted',
      });

      final chatId = _generateChatId(currentUser.uid, senderId);

      // Fetch sender data — needed for both participantsData and the notification.
      final senderDoc =
          await _firestore.collection('users').doc(senderId).get();
      final senderData =
          senderDoc.exists ? UserModel.fromMap(senderDoc.data()!) : null;

      await _firestore.collection('chats').doc(chatId).set({
        'chatId': chatId,
        'participants': [currentUser.uid, senderId],
        'participantsData': {
          currentUser.uid: {
            'username': currentUser.username,
            'avatarUrl': currentUser.avatarUrl,
          },
          senderId: {
            'username': senderData?.username ?? '',
            'avatarUrl': senderData?.avatarUrl ?? '',
          },
        },
        'lastMessage': null,
        'lastMessageTime': null,
        'unreadCount': {currentUser.uid: 0, senderId: 0},
        'lastMessageType': null,
      });

      if (senderData != null) {
        await NotificationService.sendRequestAcceptedNotification(
          receiverToken: senderData.fcmToken,
          acceptorName: currentUser.username,
          acceptorId: currentUser.uid,
          chatId: chatId,
        );
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> rejectFriendRequest(String requestId) async {
    try {
      await _firestore.collection('friendRequests').doc(requestId).delete();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> unfriend(String friendId, String friendUsername) async {
    try {
      final currentUser = ref.read(currentUserProvider).value;
      if (currentUser == null) throw Exception('Not authenticated');

      final chatId = _generateChatId(currentUser.uid, friendId);

      // 1. Delete messages subcollection FIRST (before parent doc).
      final messagesSnapshot = await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .get();

      if (messagesSnapshot.docs.isNotEmpty) {
        final batch = _firestore.batch();
        for (var doc in messagesSnapshot.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      }

      // 2. Delete the parent chat document.
      await _firestore.collection('chats').doc(chatId).delete();

      // 3. Remove friend request records (both directions) in parallel.
      final results = await Future.wait([
        _firestore
            .collection('friendRequests')
            .where('senderId', isEqualTo: currentUser.uid)
            .get(),
        _firestore
            .collection('friendRequests')
            .where('senderId', isEqualTo: friendId)
            .get(),
      ]);

      final requestBatch = _firestore.batch();
      for (var doc in results[0].docs) {
        if (doc.data()['receiverId'] == friendId) {
          requestBatch.delete(doc.reference);
        }
      }
      for (var doc in results[1].docs) {
        if (doc.data()['receiverId'] == currentUser.uid) {
          requestBatch.delete(doc.reference);
        }
      }
      await requestBatch.commit();
    } catch (e) {
      rethrow;
    }
  }

  String _generateChatId(String uid1, String uid2) {
    return uid1.hashCode <= uid2.hashCode
        ? '${uid1}_$uid2'
        : '${uid2}_$uid1';
  }
}

// ── Stream providers ────────────────────────────────────────────────────────

final receivedRequestsProvider = StreamProvider<List<FriendRequest>>((
  ref,
) async* {
  final currentUser = ref.watch(currentUserProvider).value;
  if (currentUser == null) {
    yield [];
    return;
  }

  try {
    await for (final snapshot in FirebaseFirestore.instance
        .collection('friendRequests')
        .where('receiverId', isEqualTo: currentUser.uid)
        .where('status', isEqualTo: 'pending')
        .snapshots()) {
      final stillAuthenticated = ref.read(currentUserProvider).value;
      if (stillAuthenticated == null) {
        yield [];
        return;
      }
      yield snapshot.docs
          .map((doc) => FriendRequest.fromMap(doc.data()))
          .toList();
    }
  } catch (e) {
    yield [];
  }
});

final sentRequestsProvider = StreamProvider<List<FriendRequest>>((ref) async* {
  final currentUser = ref.watch(currentUserProvider).value;
  if (currentUser == null) {
    yield [];
    return;
  }

  try {
    await for (final snapshot in FirebaseFirestore.instance
        .collection('friendRequests')
        .where('senderId', isEqualTo: currentUser.uid)
        .where('status', isEqualTo: 'pending')
        .snapshots()) {
      final stillAuthenticated = ref.read(currentUserProvider).value;
      if (stillAuthenticated == null) {
        yield [];
        return;
      }
      yield snapshot.docs
          .map((doc) => FriendRequest.fromMap(doc.data()))
          .toList();
    }
  } catch (e) {
    yield [];
  }
});

/// Streams the set of UIDs that are accepted friends of the current user.
/// Combines BOTH directions (I sent → accepted, they sent → I accepted) using
/// a StreamController so [isFriend] stays TRUE even when the chat is deleted.
final acceptedFriendsProvider = StreamProvider<Set<String>>((ref) {
  final currentUser = ref.watch(currentUserProvider).value;
  if (currentUser == null) return Stream.value({});

  final firestore = FirebaseFirestore.instance;
  final controller = StreamController<Set<String>>();

  final fromSent = <String>{};
  final fromReceived = <String>{};

  void emit() {
    if (!controller.isClosed) {
      controller.add({...fromSent, ...fromReceived});
    }
  }

  // Stream 1: requests I sent that were accepted
  final sub1 = firestore
      .collection('friendRequests')
      .where('senderId', isEqualTo: currentUser.uid)
      .where('status', isEqualTo: 'accepted')
      .snapshots()
      .listen(
    (snap) {
      fromSent
        ..clear()
        ..addAll(snap.docs.map((d) => d.data()['receiverId'] as String));
      emit();
    },
    onError: (_) => emit(),
  );

  // Stream 2: requests sent to me that I accepted
  final sub2 = firestore
      .collection('friendRequests')
      .where('receiverId', isEqualTo: currentUser.uid)
      .where('status', isEqualTo: 'accepted')
      .snapshots()
      .listen(
    (snap) {
      fromReceived
        ..clear()
        ..addAll(snap.docs.map((d) => d.data()['senderId'] as String));
      emit();
    },
    onError: (_) => emit(),
  );

  ref.onDispose(() {
    sub1.cancel();
    sub2.cancel();
    controller.close();
  });

  return controller.stream;
});
