// lib/models/user_model.dart

import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String uid;
  final String email;
  final String username;
  final String? avatarUrl;
  final bool isOnline;
  final DateTime? lastSeen;
  final String fcmToken;
  final DateTime createdAt;
  final List<String> searchKeywords;
  final List<String> blockedUsers;
  final bool isTyping;
  final String? typingInChatId;

  UserModel({
    required this.uid,
    required this.email,
    required this.username,
    this.avatarUrl,
    this.isOnline = false,
    this.lastSeen,
    required this.fcmToken,
    required this.createdAt,
    required this.searchKeywords,
    this.blockedUsers = const [],
    this.isTyping = false,
    this.typingInChatId,
  });
  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'email': email,
      'username': username,
      'avatarUrl': avatarUrl,
      'isOnline': isOnline,
      'lastSeen': lastSeen?.millisecondsSinceEpoch,
      'fcmToken': fcmToken,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'searchKeywords': searchKeywords,
      'blockedUsers': blockedUsers,
      'isTyping': isTyping,
      'typingInChatId': typingInChatId,
    };
  }

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      uid: map['uid'] as String? ?? '',
      email: map['email'] as String? ?? '',
      username: map['username'] as String? ?? '',
      avatarUrl: map['avatarUrl'] as String?,
      isOnline: map['isOnline'] as bool? ?? false,
      lastSeen: _parseDateTime(map['lastSeen']),
      fcmToken: map['fcmToken'] as String? ?? '',
      createdAt: _parseDateTime(map['createdAt']) ?? DateTime.now(),
      searchKeywords: _parseSearchKeywords(map['searchKeywords']),
      blockedUsers: _parseSearchKeywords(map['blockedUsers']),
      isTyping: map['isTyping'] as bool? ?? false,
      typingInChatId: map['typingInChatId'] as String?,
    );
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;

    try {
      if (value is Timestamp) {
        return value.toDate();
      }

      if (value is int) {
        return DateTime.fromMillisecondsSinceEpoch(value);
      }

      if (value is double) {
        return DateTime.fromMillisecondsSinceEpoch(value.toInt());
      }

      if (value is String) {
        return DateTime.parse(value);
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  static List<String> _parseSearchKeywords(dynamic value) {
    if (value == null) return [];

    try {
      if (value is List) {
        return value.map((e) => e.toString()).toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  UserModel copyWith({
    String? uid,
    String? email,
    String? username,
    String? avatarUrl,
    bool? isOnline,
    DateTime? lastSeen,
    String? fcmToken,
    DateTime? createdAt,
    List<String>? searchKeywords,
    List<String>? blockedUsers,
    bool? isTyping,
    String? typingInChatId,
  }) {
    return UserModel(
      uid: uid ?? this.uid,
      email: email ?? this.email,
      username: username ?? this.username,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      isOnline: isOnline ?? this.isOnline,
      lastSeen: lastSeen ?? this.lastSeen,
      fcmToken: fcmToken ?? this.fcmToken,
      createdAt: createdAt ?? this.createdAt,
      searchKeywords: searchKeywords ?? this.searchKeywords,
      blockedUsers: blockedUsers ?? this.blockedUsers,
      isTyping: isTyping ?? this.isTyping,
      typingInChatId: typingInChatId ?? this.typingInChatId,
    );
  }

  static List<String> generateSearchKeywords(String username) {
    List<String> keywords = [];
    String temp = "";
    for (int i = 0; i < username.length; i++) {
      temp = temp + username[i].toLowerCase();
      keywords.add(temp);
    }
    return keywords;
  }

  @override
  String toString() {
    return 'UserModel(uid: $uid, username: $username, email: $email, isOnline: $isOnline)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is UserModel && other.uid == uid;
  }

  @override
  int get hashCode => uid.hashCode;
}
