// lib/services/webrtc_service.dart
//
// WebRTC peer-to-peer call service using Firestore as the signaling channel.
//
// Signaling flow:
//   Caller:  createCall()  → writes offer to /calls/{callId}
//            → watches /calls/{callId} for answer + callee ICE candidates
//   Callee:  joinCall()   → reads offer, writes answer to /calls/{callId}
//            → watches callerCandidates subcollection
//
// Both sides exchange ICE candidates via subcollections:
//   /calls/{callId}/callerCandidates
//   /calls/{callId}/calleeCandidates

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:vibetalk/models/call_model.dart';

class WebRtcService {
  // ─── Singleton ───────────────────────────────────────────────────────────
  WebRtcService._();
  static final WebRtcService instance = WebRtcService._();

  // ─── Internal state ──────────────────────────────────────────────────────
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  final _localStreamController = StreamController<MediaStream?>.broadcast();
  final _remoteStreamController = StreamController<MediaStream?>.broadcast();
  final _callStatusController = StreamController<String>.broadcast();

  Stream<MediaStream?> get localStream => _localStreamController.stream;
  Stream<MediaStream?> get remoteStream => _remoteStreamController.stream;
  Stream<String> get callStatus => _callStatusController.stream;

  MediaStream? get currentLocalStream => _localStream;
  MediaStream? get currentRemoteStream => _remoteStream;

  // ICE candidate listener subscriptions
  StreamSubscription? _answerSub;
  StreamSubscription? _remoteIceSub;

  bool _isMuted = false;
  bool _isSpeakerOn = false;
  bool _isCameraOff = false;
  bool _isFrontCamera = true;

  // ─── Free STUN servers ───────────────────────────────────────────────────
  static const _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
    ],
  };

  static const _sdpConstraints = {
    'mandatory': {
      'OfferToReceiveAudio': true,
      'OfferToReceiveVideo': true,
    },
    'optional': [],
  };

  // =========================================================================
  // PUBLIC API
  // =========================================================================

  /// Called by the caller. Creates a Firestore /calls/{callId} document with
  /// an SDP offer. The callee will pick this up and answer.
  Future<void> createCall({
    required String callId,
    required bool isVideo,
  }) async {
    debugPrint('🔧 [WebRTC] createCall callId=$callId isVideo=$isVideo');

    await _openUserMedia(isVideo: isVideo);
    await _createPeerConnection();

    // Collect ICE candidates and write them to Firestore
    _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
      debugPrint('🧊 [WebRTC] Caller ICE: ${candidate.candidate}');
      FirebaseFirestore.instance
          .collection('calls')
          .doc(callId)
          .collection('callerCandidates')
          .add(candidate.toMap());
    };

    // Create offer
    final offer = await _peerConnection!.createOffer(_sdpConstraints);
    await _peerConnection!.setLocalDescription(offer);
    debugPrint('📤 [WebRTC] Offer created');

    // Write offer to Firestore (status already set by ConversationController)
    await FirebaseFirestore.instance.collection('calls').doc(callId).update({
      'offer': {'type': offer.type, 'sdp': offer.sdp},
    });

    // Watch for answer from callee
    _answerSub = FirebaseFirestore.instance
        .collection('calls')
        .doc(callId)
        .snapshots()
        .listen((snap) async {
      final data = snap.data();
      if (data == null) return;

      final status = data['status'] as String?;
      if (status == 'rejected' || status == 'ended') {
        _callStatusController.add(status ?? 'ended');
        return;
      }

      if (_peerConnection?.signalingState ==
          RTCSignalingState.RTCSignalingStateHaveLocalOffer) {
        final answerData = data['answer'] as Map<String, dynamic>?;
        if (answerData != null) {
          debugPrint('📥 [WebRTC] Answer received');
          final answer = RTCSessionDescription(
            answerData['sdp'] as String,
            answerData['type'] as String,
          );
          await _peerConnection!.setRemoteDescription(answer);
          _callStatusController.add('accepted');
        }
      }
    });

    // Watch callee ICE candidates
    _listenForRemoteCandidates(callId, 'calleeCandidates');
  }

  /// Called by the callee. Reads the offer, creates an answer, writes it back.
  Future<void> joinCall({
    required String callId,
    required bool isVideo,
  }) async {
    debugPrint('🔧 [WebRTC] joinCall callId=$callId isVideo=$isVideo');

    await _openUserMedia(isVideo: isVideo);
    await _createPeerConnection();

    _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
      debugPrint('🧊 [WebRTC] Callee ICE: ${candidate.candidate}');
      FirebaseFirestore.instance
          .collection('calls')
          .doc(callId)
          .collection('calleeCandidates')
          .add(candidate.toMap());
    };

    // Read the offer
    final callSnap = await FirebaseFirestore.instance
        .collection('calls')
        .doc(callId)
        .get();
    final callData = callSnap.data();
    if (callData == null) throw Exception('Call document not found');

    final offerData = callData['offer'] as Map<String, dynamic>?;
    if (offerData == null) throw Exception('No offer in call document');

    final offer = RTCSessionDescription(
      offerData['sdp'] as String,
      offerData['type'] as String,
    );
    await _peerConnection!.setRemoteDescription(offer);

    // Create answer
    final answer = await _peerConnection!.createAnswer(_sdpConstraints);
    await _peerConnection!.setLocalDescription(answer);

    // Write answer + update status
    await FirebaseFirestore.instance.collection('calls').doc(callId).update({
      'answer': {'type': answer.type, 'sdp': answer.sdp},
      'status': 'accepted',
    });
    debugPrint('📤 [WebRTC] Answer sent');

    _callStatusController.add('accepted');

    // Watch caller ICE candidates
    _listenForRemoteCandidates(callId, 'callerCandidates');
  }

  /// Ends the call: closes peer connection, updates Firestore status.
  Future<void> endCall(String callId) async {
    debugPrint('📵 [WebRTC] endCall $callId');
    try {
      await FirebaseFirestore.instance
          .collection('calls')
          .doc(callId)
          .update({'status': 'ended'});
    } catch (e) {
      debugPrint('⚠️ [WebRTC] endCall Firestore update failed: $e');
    }
    await _cleanup();
  }

  /// Rejects an incoming call without joining it.
  Future<void> rejectCall(String callId) async {
    debugPrint('🚫 [WebRTC] rejectCall $callId');
    try {
      await FirebaseFirestore.instance
          .collection('calls')
          .doc(callId)
          .update({'status': 'rejected'});
    } catch (e) {
      debugPrint('⚠️ [WebRTC] rejectCall Firestore update failed: $e');
    }
    await _cleanup();
  }

  // ─── Media controls ───────────────────────────────────────────────────────

  void toggleMute() {
    _isMuted = !_isMuted;
    _localStream?.getAudioTracks().forEach((t) => t.enabled = !_isMuted);
    debugPrint('🎙️ Muted: $_isMuted');
  }

  void toggleCamera() {
    _isCameraOff = !_isCameraOff;
    _localStream?.getVideoTracks().forEach((t) => t.enabled = !_isCameraOff);
    debugPrint('📷 Camera off: $_isCameraOff');
  }

  Future<void> switchCamera() async {
    final videoTracks = _localStream?.getVideoTracks();
    if (videoTracks != null && videoTracks.isNotEmpty) {
      await Helper.switchCamera(videoTracks.first);
      _isFrontCamera = !_isFrontCamera;
      debugPrint('🔄 Camera switched. Front: $_isFrontCamera');
    }
  }

  Future<void> toggleSpeaker() async {
    _isSpeakerOn = !_isSpeakerOn;
    await Helper.setSpeakerphoneOn(_isSpeakerOn);
    debugPrint('🔊 Speaker: $_isSpeakerOn');
  }

  bool get isMuted => _isMuted;
  bool get isCameraOff => _isCameraOff;
  bool get isSpeakerOn => _isSpeakerOn;
  bool get isFrontCamera => _isFrontCamera;

  // =========================================================================
  // PRIVATE HELPERS
  // =========================================================================

  Future<void> _openUserMedia({required bool isVideo}) async {
    final constraints = <String, dynamic>{
      'audio': true,
      'video': isVideo
          ? {'facingMode': 'user', 'width': 640, 'height': 480}
          : false,
    };

    final stream = await navigator.mediaDevices.getUserMedia(constraints);
    _localStream = stream;
    _localStreamController.add(stream);
    debugPrint(
        '📷 [WebRTC] Local stream opened. Video tracks: ${stream.getVideoTracks().length}');
  }

  Future<void> _createPeerConnection() async {
    _peerConnection = await createPeerConnection(_iceServers);
    debugPrint('🔗 [WebRTC] PeerConnection created');

    // Add local tracks to the connection
    _localStream?.getTracks().forEach((track) {
      _peerConnection!.addTrack(track, _localStream!);
    });

    // Handle incoming remote tracks
    _peerConnection!.onTrack = (RTCTrackEvent event) {
      debugPrint('📡 [WebRTC] Remote track received: ${event.track.kind}');
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams.first;
        _remoteStreamController.add(_remoteStream);
      }
    };

    _peerConnection!.onConnectionState = (RTCPeerConnectionState state) {
      debugPrint('🔌 [WebRTC] Connection state: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _callStatusController.add('ended');
      }
    };

    _peerConnection!.onIceConnectionState = (RTCIceConnectionState state) {
      debugPrint('🧊 [WebRTC] ICE state: $state');
    };
  }

  void _listenForRemoteCandidates(String callId, String subcollection) {
    _remoteIceSub?.cancel();
    _remoteIceSub = FirebaseFirestore.instance
        .collection('calls')
        .doc(callId)
        .collection(subcollection)
        .snapshots()
        .listen((snap) {
      for (final change in snap.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data();
          if (data != null) {
            final candidate = RTCIceCandidate(
              data['candidate'] as String,
              data['sdpMid'] as String,
              data['sdpMLineIndex'] as int,
            );
            _peerConnection?.addCandidate(candidate);
            debugPrint('🧊 [WebRTC] Added remote ICE candidate');
          }
        }
      }
    });
  }

  Future<void> _cleanup() async {
    await _answerSub?.cancel();
    await _remoteIceSub?.cancel();
    _answerSub = null;
    _remoteIceSub = null;

    await _localStream?.dispose();
    await _remoteStream?.dispose();
    _localStream = null;
    _remoteStream = null;

    await _peerConnection?.close();
    _peerConnection = null;

    _localStreamController.add(null);
    _remoteStreamController.add(null);

    _isMuted = false;
    _isCameraOff = false;
    _isSpeakerOn = false;
    _isFrontCamera = true;

    debugPrint('🧹 [WebRTC] Cleaned up');
  }

  /// Creates the initial Firestore call document (called before createCall).
  static Future<String> createCallDocument({
    required String callerId,
    required String callerName,
    required String? callerAvatarUrl,
    required String calleeId,
    required String calleeName,
    required bool isVideo,
  }) async {
    final callId =
        '${callerId}_${calleeId}_${DateTime.now().millisecondsSinceEpoch}';

    final call = CallModel(
      callId: callId,
      callerId: callerId,
      callerName: callerName,
      callerAvatarUrl: callerAvatarUrl,
      calleeId: calleeId,
      calleeName: calleeName,
      isVideo: isVideo,
      status: 'ringing',
      createdAt: DateTime.now(),
    );

    await FirebaseFirestore.instance
        .collection('calls')
        .doc(callId)
        .set(call.toMap());

    debugPrint('📞 [WebRTC] Call document created: $callId');
    return callId;
  }

  /// Watches a specific call document for status changes.
  static Stream<CallModel?> watchCall(String callId) {
    return FirebaseFirestore.instance
        .collection('calls')
        .doc(callId)
        .snapshots()
        .map((snap) {
      if (!snap.exists || snap.data() == null) return null;
      return CallModel.fromMap(snap.data()!);
    });
  }

  /// Watches Firestore for incoming calls where calleeId == currentUserId.
  static Stream<CallModel?> watchIncomingCalls(String currentUserId) {
    return FirebaseFirestore.instance
        .collection('calls')
        .where('calleeId', isEqualTo: currentUserId)
        .where('status', isEqualTo: 'ringing')
        .orderBy('createdAt', descending: true)
        .limit(1)
        .snapshots()
        .map((snap) {
      if (snap.docs.isEmpty) return null;
      return CallModel.fromMap(snap.docs.first.data());
    });
  }
}
