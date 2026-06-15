import 'package:flutter/material.dart';
import 'package:zego_uikit/zego_uikit.dart';
import 'package:zego_uikit_prebuilt_call/zego_uikit_prebuilt_call.dart';
import '../../providers/call_state_provider.dart';

class CallingScreen extends StatelessWidget {
  final ZegoCallingBuilderInfo callInvitationData;
  final bool isCaller;

  const CallingScreen({
    super.key,
    required this.callInvitationData,
    required this.isCaller,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CallState>(
      valueListenable: globalCallStateController,
      builder: (context, callState, child) {
        // Determine the person we are interacting with
        final ZegoUIKitUser targetUser = isCaller
            ? (callInvitationData.invitees.isNotEmpty
                  ? callInvitationData.invitees.first
                  : ZegoUIKitUser(id: '', name: 'Unknown'))
            : callInvitationData.inviter;

        // Determine status text based on state and role
        String statusText = '';
        if (isCaller) {
          if (callState == CallState.ringing) {
            statusText = 'Ringing...';
          } else {
            statusText = 'Calling...';
          }
        } else {
          statusText =
              callInvitationData.callType == ZegoCallInvitationType.videoCall
              ? 'Incoming Video Call...'
              : 'Incoming Audio Call...';
        }

        final isVideo =
            callInvitationData.callType == ZegoCallInvitationType.videoCall;

        return Scaffold(
          backgroundColor: Colors.black87,
          body: Stack(
            children: [
              // Background gradient
              Positioned.fill(
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF1a2a6c), Color(0xFF111111)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ),

              SafeArea(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Top section: Name and Status
                    Column(
                      children: [
                        const SizedBox(height: 40),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              isVideo ? Icons.videocam : Icons.phone,
                              color: Colors.white70,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              "VibeTalk",
                              style: TextStyle(
                                color: Colors.white70,
                                letterSpacing: 2,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 30),
                        Text(
                          targetUser.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          statusText,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),

                    // Center section: Avatar
                    Center(
                      child: Container(
                        width: 140,
                        height: 140,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.grey.shade800,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withAlpha(76),
                              blurRadius: 20,
                              spreadRadius: 5,
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            targetUser.name.isNotEmpty
                                ? targetUser.name[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                              fontSize: 60,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Bottom section: Controls
                    Padding(
                      padding: const EdgeInsets.only(
                        bottom: 60,
                        left: 40,
                        right: 40,
                      ),
                      child: isCaller
                          ? _buildCallerControls(context)
                          : _buildCalleeControls(context),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCallerControls(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildCircleButton(
          icon: Icons.call_end,
          color: Colors.red,
          onPressed: () async {
            final callees = callInvitationData.invitees
                .map((u) => ZegoCallUser(u.id, u.name))
                .toList();
            // Cancel the outgoing invitation on ZEGOCLOUD's side
            await ZegoUIKitPrebuiltCallInvitationService()
                .cancel(callees: callees);
            // Then dismiss this screen so the UI doesn't get stuck
            if (context.mounted) Navigator.of(context).pop();
          },
        ),
      ],
    );
  }

  Widget _buildCalleeControls(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildCircleButton(
          icon: Icons.call_end,
          color: Colors.red,
          onPressed: () async {
            await ZegoUIKitPrebuiltCallInvitationService().reject();
            // Dismiss the ringing screen after rejecting
            if (context.mounted) Navigator.of(context).pop();
          },
        ),
        _buildCircleButton(
          icon: Icons.call,
          color: Colors.green,
          onPressed: () {
            ZegoUIKitPrebuiltCallInvitationService().accept();
          },
        ),
      ],
    );
  }

  Widget _buildCircleButton({
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return InkWell(
      onTap: onPressed,
      customBorder: const CircleBorder(),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          boxShadow: [
            BoxShadow(
              color: color.withAlpha(100),
              blurRadius: 10,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Icon(icon, color: Colors.white, size: 36),
      ),
    );
  }
}
