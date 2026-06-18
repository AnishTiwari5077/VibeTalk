// lib/services/voice_recorder_service.dart

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';

class VoiceRecorderService {
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  String? _recordingPath;

  bool get isRecording => _isRecording;
  String? get recordingPath => _recordingPath;

  Future<bool> requestPermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  Future<bool> hasPermission() async {
    final status = await Permission.microphone.status;
    return status.isGranted;
  }

  Future<bool> startRecording() async {
    try {
      if (!await hasPermission()) {
        final granted = await requestPermission();
        if (!granted) return false;
      }

      final directory = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      _recordingPath = '${directory.path}/voice_$timestamp.m4a';

      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          // 64 kbps is more than enough for mono voice; 128 kbps is overkill.
          bitRate: 64000,
          // 16 kHz wideband — optimal for voice. Same quality as WhatsApp/
          // Telegram voice messages; much smaller files than 44100 Hz.
          sampleRate: 16000,
          // Mono: voice needs one channel, not stereo. Halves the file size.
          numChannels: 1,
          // Android hardware audio processing (applied in the microphone
          // hardware/DSP before the data reaches Flutter):
          autoGain: true,       // normalises quiet/loud voices
          echoCancel: true,     // removes speaker echo
          noiseSuppress: true,  // removes background noise
          androidConfig: AndroidRecordConfig(
            // VOICE_COMMUNICATION source activates hardware noise suppressor,
            // echo canceller, and AGC tuned for speech — the same pipeline
            // used by Android's phone calls and voice notes in most apps.
            audioSource: AndroidAudioSource.voiceCommunication,
          ),
        ),
        path: _recordingPath!,
      );

      _isRecording = true;
      return true;
    } catch (e) {
      debugPrint('Error starting recording: $e');
      return false;
    }
  }

  Future<String?> stopRecording() async {
    try {
      final path = await _audioRecorder.stop();
      _isRecording = false;
      return path;
    } catch (e) {
      debugPrint('Error stopping recording: $e');
      return null;
    }
  }

  Future<void> cancelRecording() async {
    try {
      await _audioRecorder.stop();
      _isRecording = false;

      if (_recordingPath != null) {
        final file = File(_recordingPath!);
        if (await file.exists()) {
          await file.delete();
        }
      }
      _recordingPath = null;
    } catch (e) {
      debugPrint('Error canceling recording: $e');
    }
  }


  /// Dispose
  void dispose() {
    _audioRecorder.dispose();
  }
}
