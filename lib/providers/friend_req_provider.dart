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
        await NotificationService.sendNotification(
          token: receiverData.fcmToken,
          title: 'New Friend Request',
          body: '${currentUser.username} sent you a friend request',
          data: {
            'type': 'friend_request',
            'senderId': currentUser.uid,
            'requestId': requestId,
          },
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
      final senderDoc = await _firestore.collection('users').doc(senderId).get();
      final senderData = senderDoc.exists
          ? UserModel.fromMap(senderDoc.data()!)
          : null;

      await _firestore.collection('chats').doc(chatId).set({
        'chatId': chatId,
        'participants': [currentUser.uid, senderId],
        // participantsData prevents a per-render fallback fetch in ChatListScreen.
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
        await NotificationService.sendNotification(
          token: senderData.fcmToken,
          title: 'Friend Request Accepted',
          body: '${currentUser.username} accepted your friend request',
          data: {
            'type': 'request_accepted',
            'userId': currentUser.uid,
            'chatId': chatId,
          },
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

      await _firestore.collection('chats').doc(chatId).delete();

      final messagesSnapshot = await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .get();

      final batch = _firestore.batch();
      for (var doc in messagesSnapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      // Run both queries in parallel — halves Firestore round-trip time.
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

      final query1 = results[0];
      final query2 = results[1];

      final requestBatch = _firestore.batch();
      for (var doc in query1.docs) {
        if (doc.data()['receiverId'] == friendId) requestBatch.delete(doc.reference);
      }
      for (var doc in query2.docs) {
        if (doc.data()['receiverId'] == currentUser.uid) requestBatch.delete(doc.reference);
      }
      await requestBatch.commit();

      final friendDoc = await _firestore
          .collection('users')
          .doc(friendId)
          .get();
      if (friendDoc.exists) {
        final friendData = UserModel.fromMap(friendDoc.data()!);
        await NotificationService.sendNotification(
          token: friendData.fcmToken,
          title: 'Friendship Ended',
          body: '${currentUser.username} removed you from their friends list',
          data: {
            'type': 'unfriend',
            'userId': currentUser.uid,
            'chatId': chatId,
          },
        );
      }
    } catch (e) {
      rethrow;
    }
  }

  String _generateChatId(String uid1, String uid2) {
    return uid1.hashCode <= uid2.hashCode ? '${uid1}_$uid2' : '${uid2}_$uid1';
  }
}

final receivedRequestsProvider = StreamProvider<List<FriendRequest>>((
  ref,
) async* {
  final currentUser = ref.watch(currentUserProvider).value;
  if (currentUser == null) {
    yield [];
    return;
  }

  try {
    await for (final snapshot
        in FirebaseFirestore.instance
            .collection('friendRequests')
            .where('receiverId', isEqualTo: currentUser.uid)
            .where('status', isEqualTo: 'pending')
            .snapshots()) {
      // Check if user is still authenticated
      final stillAuthenticated = ref.read(currentUserProvider).value;
      if (stillAuthenticated == null) {
        yield [];
        return;
      }

      final requests = snapshot.docs
          .map((doc) => FriendRequest.fromMap(doc.data()))
          .toList();

      yield requests;
    }
  } catch (e) {
    // Handle permission errors gracefully
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
    await for (final snapshot
        in FirebaseFirestore.instance
            .collection('friendRequests')
            .where('senderId', isEqualTo: currentUser.uid)
            .where('status', isEqualTo: 'pending')
            .snapshots()) {
      // Check if user is still authenticated
      final stillAuthenticated = ref.read(currentUserProvider).value;
      if (stillAuthenticated == null) {
        yield [];
        return;
      }

      final requests = snapshot.docs
          .map((doc) => FriendRequest.fromMap(doc.data()))
          .toList();

      yield requests;
    }
  } catch (e) {
    // Handle permission errors gracefully
    yield [];
  }
});
