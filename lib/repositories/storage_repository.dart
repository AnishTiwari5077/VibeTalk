// lib/repositories/storage_repository.dart

import 'dart:io';
import 'package:cloudinary_public/cloudinary_public.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:path/path.dart' as path;

class StorageRepository {
  final CloudinaryPublic _cloudinary;
  final Uuid _uuid = const Uuid();

  StorageRepository({required String cloudName, required String uploadPreset})
    : _cloudinary = CloudinaryPublic(cloudName, uploadPreset, cache: false);

  Future<String> uploadAvatar(String uid, File file) async {
    try {
      debugPrint('📤 Starting avatar upload for user: $uid');
      debugPrint('   File path: ${file.path}');

      if (!await file.exists()) {
        throw Exception('Image file does not exist at path: ${file.path}');
      }

      final fileSize = await file.length();
      debugPrint('   File size: ${fileSize / 1024} KB');

      // Cloudinary limit: 150 MB (requires paid plan; free plan = 10 MB images)
      const maxImageBytes = 150 * 1024 * 1024; // 150 MB
      if (fileSize > maxImageBytes) {
        throw Exception(
          'Avatar image is too large (${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB). '
          'Maximum allowed size is 150 MB.',
        );
      }

      // ✅ Use timestamp to create unique filename
      final timestamp = DateTime.now().millisecondsSinceEpoch;

      final response = await _cloudinary.uploadFile(
        CloudinaryFile.fromFile(
          file.path,
          folder: 'avatars/$uid',
          publicId: 'profile_$timestamp', // ✅ Changed to include timestamp
          resourceType: CloudinaryResourceType.Image,
        ),
      );

      debugPrint('✅ Avatar uploaded successfully');
      debugPrint('   Public ID: ${response.publicId}');
      debugPrint('   Secure URL: ${response.secureUrl.substring(0, response.secureUrl.length.clamp(0, 50))}...');

      return response.secureUrl;
    } on CloudinaryException catch (e) {
      debugPrint('❌ Cloudinary error: ${e.message}');
      throw Exception('Failed to upload avatar: ${e.message}');
    } catch (e) {
      debugPrint('❌ Avatar upload error: $e');
      rethrow;
    }
  }

  /// Upload avatar — alias kept for backward compat (progress not supported
  /// by cloudinary_public; use uploadAvatar instead).
  Future<String> uploadAvatarWithProgress(
    String uid,
    File file, [
    // ignore: avoid_unused_parameters
    void Function(int sent, int total)? onProgress,
  ]) async {
    try {
      debugPrint('📤 Starting avatar upload with progress for user: $uid');

      if (!await file.exists()) {
        throw Exception('Image file does not exist');
      }

      // Same 150 MB guard as uploadAvatar
      final fileSize = await file.length();
      const maxImageBytes = 150 * 1024 * 1024;
      if (fileSize > maxImageBytes) {
        throw Exception(
          'Avatar image is too large (${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB). '
          'Maximum allowed size is 150 MB.',
        );
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final response = await _cloudinary.uploadFile(
        CloudinaryFile.fromFile(
          file.path,
          folder: 'avatars/$uid',
          publicId: 'profile_$timestamp',
          resourceType: CloudinaryResourceType.Image,
        ),
      );

      debugPrint('✅ Avatar uploaded');
      return response.secureUrl;
    } catch (e) {
      debugPrint('❌ Upload error: $e');
      rethrow;
    }
  }

  /// Upload chat media (images, videos, voice messages)
  Future<String> uploadChatMedia({
    required String chatId,
    required File file,
    required String fileType, // 'image', 'video', 'voice', etc.
  }) async {
    try {
      debugPrint('📤 Starting chat media upload for chat: $chatId');
      debugPrint('   File type: $fileType');
      debugPrint('   File path: ${file.path}');

      if (!await file.exists()) {
        throw Exception('Media file does not exist');
      }

      final fileSize = await file.length();
      debugPrint('   File size: ${fileSize / (1024 * 1024)} MB');

      // Max upload limit: 150 MB for all types (requires paid Cloudinary plan)
      // Free plan limits: 10 MB images, 100 MB video/raw
      const maxBytes = 150 * 1024 * 1024; // 150 MB
      const maxLabel = '150 MB';
      if (fileSize > maxBytes) {
        throw Exception(
          'File is too large (${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB). '
          'Maximum allowed size for $fileType is $maxLabel.',
        );
      }

      final messageId = _uuid.v4();
      final fileName = path.basenameWithoutExtension(file.path);

      // Determine resource type
      final resourceType = _getResourceType(fileType);

      final response = await _cloudinary.uploadFile(
        CloudinaryFile.fromFile(
          file.path,
          folder: 'chat_media/$chatId',
          publicId: '${messageId}_$fileName',
          resourceType: resourceType,
        ),
      );

      debugPrint('✅ Chat media uploaded successfully');
      debugPrint('   Public ID: ${response.publicId}');

      return response.secureUrl;
    } on CloudinaryException catch (e) {
      debugPrint('❌ Cloudinary error: ${e.message}');
      throw Exception('Failed to upload media: ${e.message}');
    } catch (e) {
      debugPrint('❌ Chat media upload error: $e');
      rethrow;
    }
  }

  /// Delete file from Cloudinary
  Future<void> deleteFile(String url) async {
    try {
      debugPrint('🗑️ Attempting to delete file: ${url.substring(0, 50)}...');

      final publicId = _extractPublicIdFromUrl(url);

      if (publicId == null) {
        debugPrint('⚠️ Could not extract public ID from URL');
        return;
      }

      debugPrint('   Public ID: $publicId');
      debugPrint('⚠️ Deletion requires Admin API - implement on backend');
    } catch (e) {
      debugPrint('❌ Delete error: $e (ignoring)');
    }
  }

  /// Delete avatar
  Future<void> deleteAvatar(String url) async {
    await deleteFile(url);
  }

  /// Delete all user media
  Future<void> deleteAllUserMedia(String uid) async {
    try {
      debugPrint('🗑️ Deleting all media for user: $uid');
      debugPrint('⚠️ Bulk deletion requires Admin API - implement on backend');
    } catch (e) {
      debugPrint('❌ Error deleting user media: $e');
    }
  }

  /// Get resource type based on file type
  CloudinaryResourceType _getResourceType(String fileType) {
    switch (fileType.toLowerCase()) {
      case 'image':
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
        return CloudinaryResourceType.Image;
      case 'video':
      case 'mp4':
      case 'mov':
      case 'avi':
        return CloudinaryResourceType.Video;
      case 'voice': // 🆕 Voice messages are raw audio files
      case 'audio':
      case 'm4a':
      case 'mp3':
      case 'wav':
        return CloudinaryResourceType.Raw;
      case 'raw':
      default:
        return CloudinaryResourceType.Raw;
    }
  }

  /// Extract public ID from Cloudinary URL
  String? _extractPublicIdFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final pathSegments = uri.pathSegments;

      final uploadIndex = pathSegments.indexOf('upload');
      if (uploadIndex == -1 || uploadIndex + 2 >= pathSegments.length) {
        return null;
      }

      final publicIdSegments = pathSegments.sublist(uploadIndex + 2);
      final publicIdWithExtension = publicIdSegments.join('/');

      final lastDotIndex = publicIdWithExtension.lastIndexOf('.');
      if (lastDotIndex != -1) {
        return publicIdWithExtension.substring(0, lastDotIndex);
      }

      return publicIdWithExtension;
    } catch (e) {
      debugPrint('Error extracting public ID: $e');
      return null;
    }
  }

  /// Get optimized image URL with transformations
  String getOptimizedImageUrl(
    String url, {
    int? width,
    int? height,
    String quality = 'auto',
    String format = 'auto',
  }) {
    try {
      final publicId = _extractPublicIdFromUrl(url);
      if (publicId == null) return url;

      final transformations = <String>[];

      if (width != null) transformations.add('w_$width');
      if (height != null) transformations.add('h_$height');
      transformations.add('q_$quality');
      transformations.add('f_$format');

      return url.replaceFirst(
        '/upload/',
        '/upload/${transformations.join(',')}/',
      );
    } catch (e) {
      debugPrint('Error creating optimized URL: $e');
      return url;
    }
  }

  /// Get thumbnail URL
  String getThumbnailUrl(String url, {int size = 200}) {
    return getOptimizedImageUrl(
      url,
      width: size,
      height: size,
      quality: 'auto:low',
    );
  }
}
