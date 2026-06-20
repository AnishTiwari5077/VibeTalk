// lib/models/call_model.dart

class CallModel {
  final String callId;
  final String callerId;
  final String callerName;
  final String? callerAvatarUrl;
  final String calleeId;
  final String calleeName;
  final bool isVideo;
  // 'ringing' | 'accepted' | 'rejected' | 'ended'
  // Note: receiverOnline (bool) is a separate Firestore field written by
  // IncomingCallScreen — it is NOT stored in CallModel; CallingScreen reads
  // it directly from the raw snapshot to switch 'Calling...' → 'Ringing...'.
  final String status;
  final Map<String, dynamic>? offer;
  final Map<String, dynamic>? answer;
  final DateTime createdAt;

  const CallModel({
    required this.callId,
    required this.callerId,
    required this.callerName,
    this.callerAvatarUrl,
    required this.calleeId,
    required this.calleeName,
    required this.isVideo,
    required this.status,
    this.offer,
    this.answer,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'callId': callId,
        'callerId': callerId,
        'callerName': callerName,
        'callerAvatarUrl': callerAvatarUrl,
        'calleeId': calleeId,
        'calleeName': calleeName,
        'isVideo': isVideo,
        'status': status,
        'offer': offer,
        'answer': answer,
        'createdAt': createdAt.millisecondsSinceEpoch,
      };

  factory CallModel.fromMap(Map<String, dynamic> map) => CallModel(
        callId: map['callId'] as String? ?? '',
        callerId: map['callerId'] as String? ?? '',
        callerName: map['callerName'] as String? ?? '',
        callerAvatarUrl: map['callerAvatarUrl'] as String?,
        calleeId: map['calleeId'] as String? ?? '',
        calleeName: map['calleeName'] as String? ?? '',
        isVideo: map['isVideo'] as bool? ?? false,
        status: map['status'] as String? ?? 'ringing',
        offer: map['offer'] as Map<String, dynamic>?,
        answer: map['answer'] as Map<String, dynamic>?,
        createdAt: map['createdAt'] != null
            ? DateTime.fromMillisecondsSinceEpoch(map['createdAt'] as int)
            : DateTime.now(),
      );

  CallModel copyWith({String? status, Map<String, dynamic>? answer}) =>
      CallModel(
        callId: callId,
        callerId: callerId,
        callerName: callerName,
        callerAvatarUrl: callerAvatarUrl,
        calleeId: calleeId,
        calleeName: calleeName,
        isVideo: isVideo,
        status: status ?? this.status,
        offer: offer,
        answer: answer ?? this.answer,
        createdAt: createdAt,
      );
}
