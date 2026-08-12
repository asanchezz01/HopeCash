import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hopecash/core/audio/hope_audio_source.dart';
import 'package:just_audio/just_audio.dart';

void main() {
  test(
    'cria arquivo WAV com extensão reconhecida pelo player nativo',
    () async {
      final bytes = Uint8List.fromList([
        0x52,
        0x49,
        0x46,
        0x46,
        0x04,
        0x00,
        0x00,
        0x00,
        0x57,
        0x41,
        0x56,
        0x45,
      ]);

      final playbackSource = await createHopeAudioPlaybackSource(
        bytes,
        'audio/wav',
      );
      addTearDown(playbackSource.dispose);

      final source = playbackSource.audioSource as UriAudioSource;
      expect(source.uri.scheme, 'file');
      expect(source.uri.path, endsWith('.wav'));
      expect(await File.fromUri(source.uri).readAsBytes(), bytes);
    },
  );

  test(
    'prioriza a assinatura MP3 quando o cabeçalho MIME é genérico',
    () async {
      final bytes = Uint8List.fromList([0x49, 0x44, 0x33, 0x04, 0x00]);

      final playbackSource = await createHopeAudioPlaybackSource(
        bytes,
        'application/octet-stream',
      );
      addTearDown(playbackSource.dispose);

      final source = playbackSource.audioSource as UriAudioSource;
      expect(source.uri.path, endsWith('.mp3'));
    },
  );
}
