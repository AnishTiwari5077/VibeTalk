import 'package:cloud_firestore/cloud_firestore.dart';

class ChatModel {
  final String chatId;
  final List<String> participants;
  final String? lastMessage;
  final DateTime? lastMessageTime;
  final Map<String, int> unreadCount;
  final Map<String, Map<String, dynamic>>? participantsData;

  ChatModel({
    required this.chatId,
    required this.participants,
    this.lastMessage,
    this.lastMessageTime,
    required this.unreadCount,
    this.participantsData,
  });

  Map<String, dynamic> toMap() {
    return {
      'chatId': chatId,
      'participants': participants,
      'lastMessage': lastMessage,
      'lastMessageTime': lastMessageTime?.millisecondsSinceEpoch,
      'unreadCount': unreadCount,
      'participantsData': participantsData,
    };
  }

  factory ChatModel.fromMap(Map<String, dynamic> map) {
    return ChatModel(
      chatId: map['chatId']?.toString() ?? '',
      participants: List<String>.from(
        (map['participants'] ?? []).map((e) => e.toString()),
      ),
      lastMessage: map['lastMessage']?.toString(),
      lastMessageTime: _parseDate(map['lastMessageTime']),
      unreadCount: _parseUnread(map['unreadCount']),
      participantsData: _parseParticipantsData(map['participantsData']),
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;

    try {
      if (value is Timestamp) return value.toDate();
      if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
      if (value is double) {
        return DateTime.fromMillisecondsSinceEpoch(value.toInt());
      }
      if (value is String) return DateTime.tryParse(value);
    } catch (_) {}

    return null;
  }

  static Map<String, int> _parseUnread(dynamic value) {
    if (value == null) return {};

    try {
      final raw = Map<String, dynamic>.from(value);
      return raw.map(
        (key, val) =>
            MapEntry(key.toString(), (val is int) ? val : (val ?? 0).toInt()),
      );
    } catch (_) {
      return {};
    }
  }

  static Map<String, Map<String, dynamic>>? _parseParticipantsData(
    dynamic value,
  ) {
    if (value == null) return null;

    try {
      final raw = Map<String, dynamic>.from(value);
      return raw.map(
        (key, val) =>
            MapEntry(key.toString(), Map<String, dynamic>.from(val as Map)),
      );
    } catch (_) {
      return null;
    }
  }
}
