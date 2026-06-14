import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../models/user_model.dart';

class AuthRepository {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  Future<UserCredential> signInWithEmailAndPassword(
    String email,
    String password,
  ) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (credential.user != null) {
        final fcmToken = await _messaging.getToken() ?? '';

        await _firestore.collection('users').doc(credential.user!.uid).set({
          'isOnline': true,
          'fcmToken': fcmToken,
          'lastSeen': DateTime.now().millisecondsSinceEpoch,
        }, SetOptions(merge: true));
      }

      return credential;
    } catch (e) {
      rethrow;
    }
  }

  Future<UserCredential> signUpWithEmailAndPassword({
    required String email,
    required String password,
    required String username,
    String? avatarUrl,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (credential.user != null) {
        final fcmToken = await _messaging.getToken() ?? '';

        final userModel = UserModel(
          uid: credential.user!.uid,
          email: email,
          username: username,
          avatarUrl: avatarUrl,
          isOnline: true,
          lastSeen: DateTime.now(),
          fcmToken: fcmToken,
          createdAt: DateTime.now(),
          searchKeywords: UserModel.generateSearchKeywords(username),
        );

        await _firestore
            .collection('users')
            .doc(credential.user!.uid)
            .set(userModel.toMap());
      }

      return credential;
    } catch (e) {
      rethrow;
    }
  }

  Future<void> signOut() async {
    try {
      if (currentUser != null) {
        // Update user status and clear FCM token before signing out
        await _firestore.collection('users').doc(currentUser!.uid).set({
          'isOnline': false,
          'lastSeen': DateTime.now().millisecondsSinceEpoch,
          'fcmToken': '', // Clear FCM token
          'isTyping': false, // Clear typing status
          'typingInChatId': null,
        }, SetOptions(merge: true));
      }

      // Sign out from Firebase Auth
      await _auth.signOut();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> updateOnlineStatus(bool isOnline) async {
    try {
      if (currentUser != null) {
        await _firestore.collection('users').doc(currentUser!.uid).set({
          'isOnline': isOnline,
          'lastSeen': DateTime.now().millisecondsSinceEpoch,
        }, SetOptions(merge: true));
      }
    } catch (e) {
      rethrow;
    }
  }
}
