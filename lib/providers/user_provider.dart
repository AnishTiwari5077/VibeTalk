import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart' show StateProvider;
import '../models/user_model.dart';

import 'auth_provider.dart';

final userStreamProvider = StreamProvider.family<UserModel?, String>((
  ref,
  uid,
) {
  return ref.watch(userRepositoryProvider).getUserStream(uid);
});

final allUsersProvider = StreamProvider<List<UserModel>>((ref) async* {
  final currentUser = ref.watch(currentUserProvider).value;
  if (currentUser == null) {
    yield [];
    return;
  }

  final userRepository = ref.read(userRepositoryProvider);

  try {
    await for (final users in userRepository.getAllUsers(currentUser.uid)) {
      // Check if user is still authenticated
      final stillAuthenticated = ref.read(currentUserProvider).value;
      if (stillAuthenticated == null) {
        yield [];
        return;
      }

      final filteredUsers = <UserModel>[];
      for (final user in users) {
        final isBlocked = await userRepository.isUserBlocked(
          currentUser.uid,
          user.uid,
        );
        if (!isBlocked) {
          filteredUsers.add(user);
        }
      }
      yield filteredUsers;
    }
  } catch (e) {
    // Handle permission errors gracefully
    yield [];
  }
});

final searchQueryProvider = StateProvider<String>((ref) => '');

final filteredUsersProvider = StreamProvider<List<UserModel>>((ref) async* {
  final query = ref.watch(searchQueryProvider);
  final currentUser = ref.watch(currentUserProvider).value;

  if (currentUser == null) {
    yield [];
    return;
  }

  final userRepository = ref.read(userRepositoryProvider);

  try {
    Stream<List<UserModel>> userStream;
    if (query.isEmpty) {
      userStream = userRepository.getAllUsers(currentUser.uid);
    } else {
      userStream = userRepository.searchUsers(query, currentUser.uid);
    }

    await for (final users in userStream) {
      // Check if user is still authenticated
      final stillAuthenticated = ref.read(currentUserProvider).value;
      if (stillAuthenticated == null) {
        yield [];
        return;
      }

      // Filter out blocked users
      final filteredUsers = <UserModel>[];
      for (final user in users) {
        final isBlocked = await userRepository.isUserBlocked(
          currentUser.uid,
          user.uid,
        );
        if (!isBlocked) {
          filteredUsers.add(user);
        }
      }
      yield filteredUsers;
    }
  } catch (e) {
    // Handle permission errors gracefully
    yield [];
  }
});
