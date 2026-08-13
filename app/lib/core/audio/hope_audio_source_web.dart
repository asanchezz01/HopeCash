import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';

class HopeAudioSource {
  HopeAudioSource._(this.source);

  final AudioSource source;

  static Future<HopeAudioSource> fromBytes(
    Uint8List bytes,
    String contentType,
  ) async {
    final uri = Uri.dataFromBytes(bytes, mimeType: contentType);
    return HopeAudioSource._(AudioSource.uri(uri));
  }

  Future<void> dispose() async {}
}
