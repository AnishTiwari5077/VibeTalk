import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibetalk/core/date_formattor.dart';
import 'package:vibetalk/core/error_handler.dart';
import 'package:vibetalk/providers/friend_req_provider.dart';
import 'package:vibetalk/widgets/empty_state.dart';
import 'package:vibetalk/widgets/user_avatar.dart';

import '../../providers/user_provider.dart';

class RequestsScreen extends ConsumerWidget {
  const RequestsScreen({super.key});

  Future<void> _acceptRequest(
    BuildContext context,
    WidgetRef ref,
    String requestId,
    String senderId,
  ) async {
    try {
      final confirm = await ErrorHandler.showConfirmDialog(
        context,
        'Accept Friend Request',
        'Do you want to accept this friend request?',
      );

      if (!confirm) return;

      await ref
          .read(friendRequestProvider)
          .acceptFriendRequest(requestId, senderId);

      if (context.mounted) {
        ErrorHandler.showSuccessSnackBar(context, 'Friend request accepted');
      }
    } catch (e) {
      if (context.mounted) {
        ErrorHandler.showErrorSnackBar(
          context,
          ErrorHandler.getErrorMessage(e),
        );
      }
    }
  }

  Future<void> _rejectRequest(
    BuildContext context,
    WidgetRef ref,
    String requestId,
  ) async {
    try {
      final confirm = await ErrorHandler.showConfirmDialog(
        context,
        'Reject Friend Request',
        'Do you want to reject this friend request?',
      );

      if (!confirm) return;

      await ref.read(friendRequestProvider).rejectFriendRequest(requestId);

      if (context.mounted) {
        ErrorHandler.showSuccessSnackBar(context, 'Friend request rejected');
      }
    } catch (e) {
      if (context.mounted) {
        ErrorHandler.showErrorSnackBar(
          context,
          ErrorHandler.getErrorMessage(e),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final receivedRequestsAsync = ref.watch(receivedRequestsProvider);
    final sentRequestsAsync = ref.watch(sentRequestsProvider);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Friend Requests'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Received'),
              Tab(text: 'Sent'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // Received Requests Tab
            receivedRequestsAsync.when(
              data: (requests) {
                if (requests.isEmpty) {
                  return const EmptyState(
                    icon: Icons.inbox_outlined,
                    message: 'No pending requests',
                    subtitle: 'Friend requests will appear here',
                  );
                }

                return ListView.builder(
                  itemCount: requests.length,
                  itemBuilder: (context, index) {
                    final request = requests[index];

                    return Consumer(
                      builder: (context, ref, child) {
                        final senderAsync = ref.watch(
                          userStreamProvider(request.senderId),
                        );

                        return senderAsync.when(
                          data: (sender) {
                            if (sender == null) return const SizedBox.shrink();

                            return Card(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              child: ListTile(
                                leading: UserAvatar(
                                  imageUrl: sender.avatarUrl,
                                  showOnlineIndicator: true,
                                  isOnline: sender.isOnline,
                                ),
                                title: Text(sender.username),
                                subtitle: Text(
                                  DateFormatter.formatMessageTime(
                                    request.timestamp,
                                  ),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    ElevatedButton(
                                      onPressed: () => _acceptRequest(
                                        context,
                                        ref,
                                        request.id,
                                        request.senderId,
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 6,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                      ),
                                      child: const Text(
                                        'Confirm',
                                        style: TextStyle(fontSize: 12),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    OutlinedButton(
                                      onPressed: () => _rejectRequest(
                                        context,
                                        ref,
                                        request.id,
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.red,
                                        side: const BorderSide(
                                          color: Colors.red,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 6,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                      ),
                                      child: const Text(
                                        'Reject',
                                        style: TextStyle(fontSize: 12),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                          loading: () => const Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                child: CircularProgressIndicator(),
                              ),
                              title: Text('Loading...'),
                            ),
                          ),
                          error: (_, _) => const SizedBox.shrink(),
                        );
                      },
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => Center(child: Text('Error: $error')),
            ),

            // Sent Requests Tab
            sentRequestsAsync.when(
              data: (requests) {
                if (requests.isEmpty) {
                  return const EmptyState(
                    icon: Icons.send_outlined,
                    message: 'No sent requests',
                    subtitle: 'Requests you send will appear here',
                  );
                }

                return ListView.builder(
                  itemCount: requests.length,
                  itemBuilder: (context, index) {
                    final request = requests[index];

                    return Consumer(
                      builder: (context, ref, child) {
                        final receiverAsync = ref.watch(
                          userStreamProvider(request.receiverId),
                        );

                        return receiverAsync.when(
                          data: (receiver) {
                            if (receiver == null) {
                              return const SizedBox.shrink();
                            }

                            return Card(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              child: ListTile(
                                leading: UserAvatar(
                                  imageUrl: receiver.avatarUrl,
                                ),
                                title: Text(receiver.username),
                                subtitle: Text(
                                  DateFormatter.formatMessageTime(
                                    request.timestamp,
                                  ),
                                ),
                                trailing: const Chip(
                                  label: Text('Pending'),
                                  backgroundColor: Colors.orange,
                                ),
                              ),
                            );
                          },
                          loading: () => const Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                child: CircularProgressIndicator(),
                              ),
                              title: Text('Loading...'),
                            ),
                          ),
                          error: (_, _) => const SizedBox.shrink(),
                        );
                      },
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => Center(child: Text('Error: $error')),
            ),
          ],
        ),
      ),
    );
  }
}
