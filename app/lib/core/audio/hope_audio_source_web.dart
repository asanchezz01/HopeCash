import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';

class HopeAudioPlaybackSource {
  HopeAudioPlaybackSource(this.audioSource);

  final AudioSource audioSource;

  Future<void> dispose() async {}
}

Future<HopeAudioPlaybackSource> createHopeAudioPlaybackSource(
  Uint8List bytes,
  String contentType,
) async {
  final uri = Uri.dataFromBytes(bytes, mimeType: contentType);
  return HopeAudioPlaybackSource(AudioSource.uri(uri));
}
