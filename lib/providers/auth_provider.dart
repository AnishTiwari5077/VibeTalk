import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../repositories/auth_repository.dart';
import '../repositories/user_repository.dart';
import '../models/user_model.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository();
});

final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges;
});

final currentUserProvider = StreamProvider<UserModel?>((ref) async* {
  final authStateAsync = ref.watch(authStateProvider);

  // Wait for auth state to load
  if (authStateAsync.isLoading) {
    yield null;
    return;
  }

  // Handle errors in auth state
  if (authStateAsync.hasError) {
    yield null;
    return;
  }

  // Get the user from auth state
  final user = authStateAsync.value;

  if (user == null) {
    yield null;
  } else {
    final userRepository = ref.read(userRepositoryProvider);
    try {
      await for (final userModel in userRepository.getUserStream(user.uid)) {
        yield userModel;
      }
    } catch (e) {
      // Handle errors gracefully (e.g., permission denied after logout)
      yield null;
    }
  }
});

// Auth service to handle logout with proper cleanup
final authServiceProvider = Provider((ref) => AuthService(ref));

class AuthService {
  final Ref ref;

  AuthService(this.ref);

  Future<void> logout() async {
    try {
      // Sign out from Firebase first
      await ref.read(authRepositoryProvider).signOut();

      // Invalidate all providers to clean up listeners
      ref.invalidate(currentUserProvider);
      ref.invalidate(authStateProvider);
    } catch (e) {
      rethrow;
    }
  }
}

final userRepositoryProvider = Provider<UserRepository>((ref) {
  return UserRepository();
});
