import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibetalk/models/user_model.dart';
import 'package:vibetalk/providers/auth_provider.dart';

/// Streams a [UserModel] by UID with real-time Firestore updates.
///
/// Using a [StreamProvider] instead of a [FutureProvider] means any change to
/// the user document (avatar, username, online status) is reflected immediately
/// on every device — no 5-minute cache delay.
///
/// The API is identical to the old FutureProvider so all consumers
/// (chat list, profile) need no changes.
final userCacheProvider =
    StreamProvider.family.autoDispose<UserModel?, String>(
  (ref, uid) {
    return ref.read(userRepositoryProvider).getUserStream(uid);
  },
);
