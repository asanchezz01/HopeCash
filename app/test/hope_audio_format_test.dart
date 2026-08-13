import 'package:flutter_test/flutter_test.dart';
import 'package:hopecash/core/audio/hope_audio_format.dart';

void main() {
  test('usa extensão mp3 para o áudio MPEG devolvido pelo Azure', () {
    expect(hopeAudioFileExtension('audio/mpeg'), 'mp3');
    expect(hopeAudioFileExtension('audio/mpeg; charset=binary'), 'mp3');
  });

  test('preserva extensões conhecidas e usa mp3 como fallback', () {
    expect(hopeAudioFileExtension('audio/wav'), 'wav');
    expect(hopeAudioFileExtension('audio/aac'), 'm4a');
    expect(hopeAudioFileExtension('application/octet-stream'), 'mp3');
  });
}
