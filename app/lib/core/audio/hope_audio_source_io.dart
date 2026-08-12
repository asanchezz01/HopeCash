import 'dart:io';
import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';

class HopeAudioPlaybackSource {
  HopeAudioPlaybackSource(this.audioSource, this._directory);

  final AudioSource audioSource;
  final Directory _directory;

  Future<void> dispose() async {
    if (await _directory.exists()) {
      await _directory.delete(recursive: true);
    }
  }
}

Future<HopeAudioPlaybackSource> createHopeAudioPlaybackSource(
  Uint8List bytes,
  String contentType,
) async {
  final directory = await Directory.systemTemp.createTemp(
    'hopecash_hope_voice_',
  );
  try {
    final extension = hopeAudioFileExtension(bytes, contentType);
    final file = File(
      '${directory.path}${Platform.pathSeparator}speech.$extension',
    );
    await file.writeAsBytes(bytes, flush: true);
    return HopeAudioPlaybackSource(AudioSource.uri(file.uri), directory);
  } catch (_) {
    await directory.delete(recursive: true);
    rethrow;
  }
}

String hopeAudioFileExtension(Uint8List bytes, String contentType) {
  if (_startsWith(bytes, const [0x52, 0x49, 0x46, 0x46]) &&
      bytes.length >= 12 &&
      _matchesAt(bytes, 8, const [0x57, 0x41, 0x56, 0x45])) {
    return 'wav';
  }
  if (_startsWith(bytes, const [0x49, 0x44, 0x33]) ||
      (bytes.length >= 2 && bytes[0] == 0xff && (bytes[1] & 0xe0) == 0xe0)) {
    return 'mp3';
  }
  if (_startsWith(bytes, const [0x4f, 0x67, 0x67, 0x53])) return 'ogg';
  if (_startsWith(bytes, const [0x66, 0x4c, 0x61, 0x43])) return 'flac';
  if (bytes.length >= 12 &&
      _matchesAt(bytes, 4, const [0x66, 0x74, 0x79, 0x70])) {
    return 'm4a';
  }

  return switch (contentType.toLowerCase().split(';').first.trim()) {
    'audio/mpeg' || 'audio/mp3' => 'mp3',
    'audio/wav' || 'audio/x-wav' || 'audio/wave' => 'wav',
    'audio/ogg' || 'audio/opus' => 'ogg',
    'audio/flac' || 'audio/x-flac' => 'flac',
    'audio/mp4' || 'audio/x-m4a' || 'audio/m4a' => 'm4a',
    _ => 'mp3',
  };
}

bool _startsWith(Uint8List bytes, List<int> signature) =>
    _matchesAt(bytes, 0, signature);

bool _matchesAt(Uint8List bytes, int offset, List<int> signature) {
  if (bytes.length < offset + signature.length) return false;
  for (var i = 0; i < signature.length; i++) {
    if (bytes[offset + i] != signature[i]) return false;
  }
  return true;
}
