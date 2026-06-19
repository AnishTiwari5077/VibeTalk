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
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;
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

  // Bug fix: buffer ICE candidates that arrive before setRemoteDescription
  final List<RTCIceCandidate> _pendingCandidates = [];
  bool _remoteDescriptionSet = false;

  bool _isMuted = false;
  bool _isSpeakerOn = false;
  bool _isCameraOff = false;
  bool _isFrontCamera = true;
  // Guard: prevents createCall/joinCall being called while already in progress
  // (happens when the same notification is processed twice).
  bool _isCallInProgress = false;

  // ─── ICE server fallback (used only if API fetch fails) ─────────────────
  static const _fallbackIceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
  };

  /// Fetches fresh, time-limited TURN credentials from Metered.ca REST API.
  /// Falls back to STUN-only if the network request fails.
  static Future<Map<String, dynamic>> _fetchIceServers() async {
    const apiKey = '8bf8c611614a7e8c7b77c991e03524cf22b8';
    const url =
        'https://chartapp.metered.live/api/v1/turn/credentials?apiKey=$apiKey';
    try {
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final List<dynamic> servers =
            jsonDecode(response.body) as List<dynamic>;
        debugPrint(
          '🌐 [WebRTC] Fetched ${servers.length} ICE servers from Metered.ca',
        );
        return {'iceServers': servers};
      }
      debugPrint(
        '⚠️ [WebRTC] Metered API returned ${response.statusCode} — using fallback',
      );
    } catch (e) {
      debugPrint(
        '⚠️ [WebRTC] Could not fetch TURN credentials: $e — using fallback',
      );
    }
    return _fallbackIceServers;
  }

  static const _sdpConstraints = {
    'mandatory': {'OfferToReceiveAudio': true, 'OfferToReceiveVideo': true},
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
    if (_isCallInProgress) {
      debugPrint('⚠️ [WebRTC] createCall ignored — call already in progress');
      return;
    }
    _isCallInProgress = true;

    await _openUserMedia(isVideo: isVideo);
    final iceServers = await _fetchIceServers();
    await _createPeerConnection(iceServers);

    // Collect ICE candidates and write them to Firestore
    _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
      debugPrint('🧊 [WebRTC] Caller ICE: ${candidate.candidate}');
      FirebaseFirestore.instance
          .collection('calls')
          .doc(callId)
          .collection('callerCandidates')
          .add(candidate.toMap());
    };

    // Create offer — modify SDP BEFORE setLocalDescription to avoid mismatch
    final rawOffer = await _peerConnection!.createOffer(_sdpConstraints);
    final optimizedOfferSdp = _optimizeSdpBitrate(
      rawOffer.sdp!,
      targetBitrateKbps: isVideo ? 2500 : 128,
      isVideo: isVideo,
    );
    final offer = RTCSessionDescription(optimizedOfferSdp, rawOffer.type);
    await _peerConnection!.setLocalDescription(offer);
    debugPrint(
      '📤 [WebRTC] Offer created (${isVideo ? "2500 kbps video" : "128 kbps audio"})',
    );

    // Write offer to Firestore
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
              // Flush any ICE candidates that arrived before answer
              _remoteDescriptionSet = true;
              for (final c in _pendingCandidates) {
                await _peerConnection?.addCandidate(c);
                debugPrint(
                  '🧊 [WebRTC] Flushed buffered ICE candidate (caller)',
                );
              }
              _pendingCandidates.clear();
              _callStatusController.add('accepted');
            }
          }
        });

    // Watch callee ICE candidates
    _listenForRemoteCandidates(callId, 'calleeCandidates');
  }

  /// Called by the callee. Reads the offer, creates an answer, writes it back.
  Future<void> joinCall({required String callId, required bool isVideo}) async {
    debugPrint('🔧 [WebRTC] joinCall callId=$callId isVideo=$isVideo');
    if (_isCallInProgress) {
      debugPrint('⚠️ [WebRTC] joinCall ignored — call already in progress');
      return;
    }
    _isCallInProgress = true;

    await _openUserMedia(isVideo: isVideo);
    final iceServers = await _fetchIceServers();
    await _createPeerConnection(iceServers);

    _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
      debugPrint('🧊 [WebRTC] Callee ICE: ${candidate.candidate}');
      FirebaseFirestore.instance
          .collection('calls')
          .doc(callId)
          .collection('calleeCandidates')
          .add(candidate.toMap());
    };

    // Wait for offer to appear (up to 15 s) — fixes the race condition where
    // the callee's screen opens before the caller has written the offer to
    // Firestore (which happens asynchronously after the call document is created).
    debugPrint('⏳ [WebRTC] Waiting for offer in Firestore...');
    final offerCompleter = Completer<Map<String, dynamic>>();
    StreamSubscription? offerSub;
    offerSub = FirebaseFirestore.instance
        .collection('calls')
        .doc(callId)
        .snapshots()
        .listen((snap) {
          final data = snap.data();
          if (data != null &&
              data['offer'] != null &&
              !offerCompleter.isCompleted) {
            offerSub?.cancel();
            offerCompleter.complete(data['offer'] as Map<String, dynamic>);
          }
        });

    late Map<String, dynamic> offerData;
    try {
      offerData = await offerCompleter.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          offerSub?.cancel();
          throw Exception('Timed out waiting for offer after 15 s');
        },
      );
    } catch (e) {
      offerSub.cancel();
      rethrow;
    }
    debugPrint('✅ [WebRTC] Offer received from Firestore');

    final offer = RTCSessionDescription(
      offerData['sdp'] as String,
      offerData['type'] as String,
    );
    await _peerConnection!.setRemoteDescription(offer);

    // Create answer — modify SDP BEFORE setLocalDescription to avoid mismatch
    final rawAnswer = await _peerConnection!.createAnswer(_sdpConstraints);
    final optimizedAnswerSdp = _optimizeSdpBitrate(
      rawAnswer.sdp!,
      targetBitrateKbps: isVideo ? 2500 : 128,
      isVideo: isVideo,
    );
    final answer = RTCSessionDescription(optimizedAnswerSdp, rawAnswer.type);
    await _peerConnection!.setLocalDescription(answer);
    debugPrint(
      '📤 [WebRTC] Answer sent (${isVideo ? "2500 kbps video" : "128 kbps audio"})',
    );

    // Mark remote description as set and flush any buffered ICE candidates
    _remoteDescriptionSet = true;
    for (final c in _pendingCandidates) {
      await _peerConnection?.addCandidate(c);
      debugPrint('🧊 [WebRTC] Flushed buffered ICE candidate');
    }
    _pendingCandidates.clear();

    // Write answer + update status
    await FirebaseFirestore.instance.collection('calls').doc(callId).update({
      'answer': {'type': answer.type, 'sdp': answer.sdp},
      'status': 'accepted',
    });

    _callStatusController.add('accepted');

    // Watch caller ICE candidates
    _listenForRemoteCandidates(callId, 'callerCandidates');
  }

  /// Ends the call: closes peer connection, updates Firestore status.
  Future<void> endCall(String callId) async {
    debugPrint('📵 [WebRTC] endCall $callId');
    try {
      await FirebaseFirestore.instance.collection('calls').doc(callId).update({
        'status': 'ended',
      });
    } catch (e) {
      debugPrint('⚠️ [WebRTC] endCall Firestore update failed: $e');
    }
    await _cleanup();
  }

  /// Rejects an incoming call without joining it.
  Future<void> rejectCall(String callId) async {
    debugPrint('🚫 [WebRTC] rejectCall $callId');
    try {
      await FirebaseFirestore.instance.collection('calls').doc(callId).update({
        'status': 'rejected',
      });
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
      // Optimized audio: noise suppression + echo cancellation
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      // Use 'ideal' (not 'mandatory') so getUserMedia gracefully falls back
      // on devices that don't support 720p instead of throwing an error.
      'video': isVideo
          ? {
              'facingMode': 'user',
              'width': {'ideal': 1280},
              'height': {'ideal': 720},
              'frameRate': {'ideal': 30, 'max': 30},
            }
          : false,
    };

    final stream = await navigator.mediaDevices.getUserMedia(constraints);
    _localStream = stream;
    _localStreamController.add(stream);
    debugPrint(
      '📷 [WebRTC] Local stream opened. Video tracks: ${stream.getVideoTracks().length}',
    );
  }

  /// Injects a bandwidth limit into the SDP to prevent WebRTC from
  /// over-compressing the stream on mobile networks.
  /// [targetBitrateKbps] — 2500 for video calls, 128 for audio-only.
  String _optimizeSdpBitrate(
    String sdp, {
    required int targetBitrateKbps,
    bool isVideo = true,
  }) {
    final lines = sdp.split('\r\n');
    final marker = isVideo ? 'm=video' : 'm=audio';
    final idx = lines.indexWhere((l) => l.startsWith(marker));
    if (idx != -1) {
      lines.insert(idx + 1, 'b=AS:$targetBitrateKbps');
    }
    return lines.join('\r\n');
  }

  Future<void> _createPeerConnection(Map<String, dynamic> iceServers) async {
    _peerConnection = await createPeerConnection(iceServers);
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
                // Buffer candidates until remoteDescription is set — adding them
                // before setRemoteDescription silently drops them and breaks ICE.
                if (_remoteDescriptionSet) {
                  _peerConnection?.addCandidate(candidate);
                  debugPrint('🧊 [WebRTC] Added remote ICE candidate');
                } else {
                  _pendingCandidates.add(candidate);
                  debugPrint(
                    '🧊 [WebRTC] Buffered ICE candidate (remote desc not set yet)',
                  );
                }
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

    _pendingCandidates.clear();
    _remoteDescriptionSet = false;
    _isCallInProgress = false;

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
  /// Only emits calls created within the last 90 seconds to prevent stale
  /// call documents from triggering IncomingCallScreen on app restart.
  /// The staleness check is done client-side to avoid a composite index.
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
          final call = CallModel.fromMap(snap.docs.first.data());
          // Client-side staleness guard: ignore calls older than 90 s
          final age = DateTime.now().difference(call.createdAt);
          if (age.inSeconds > 90) return null;
          return call;
        });
  }
}
