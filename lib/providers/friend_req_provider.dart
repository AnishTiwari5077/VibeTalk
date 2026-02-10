import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:new_chart/services/notification_services.dart';
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
      await _firestore.collection('chats').doc(chatId).set({
        'chatId': chatId,
        'participants': [currentUser.uid, senderId],
        'lastMessage': null,
        'lastMessageTime': null,
        'unreadCount': {currentUser.uid: 0, senderId: 0},
        'lastMessageType': null,
      });

      final senderDoc = await _firestore
          .collection('users')
          .doc(senderId)
          .get();
      if (senderDoc.exists) {
        final senderData = UserModel.fromMap(senderDoc.data()!);
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

      final friendRequestsSnapshot = await _firestore
          .collection('friendRequests')
          .where('status', isEqualTo: 'accepted')
          .get();

      final requestsToDelete = friendRequestsSnapshot.docs.where((doc) {
        final data = doc.data();
        return (data['senderId'] == currentUser.uid &&
                data['receiverId'] == friendId) ||
            (data['senderId'] == friendId &&
                data['receiverId'] == currentUser.uid);
      });

      final requestBatch = _firestore.batch();
      for (var doc in requestsToDelete) {
        requestBatch.delete(doc.reference);
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
