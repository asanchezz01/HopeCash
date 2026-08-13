import 'dart:io';
import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import 'hope_audio_format.dart';

class HopeAudioSource {
  HopeAudioSource._(this.source, this._file);

  final AudioSource source;
  final File _file;

  static Future<HopeAudioSource> fromBytes(
    Uint8List bytes,
    String contentType,
  ) async {
    final directory = await getTemporaryDirectory();
    final extension = hopeAudioFileExtension(contentType);
    final file = File(
      '${directory.path}${Platform.pathSeparator}'
      'hope_tts_${DateTime.now().microsecondsSinceEpoch}.$extension',
    );
    await file.writeAsBytes(bytes, flush: true);
    return HopeAudioSource._(AudioSource.file(file.path), file);
  }

  Future<void> dispose() async {
    try {
      if (await _file.exists()) await _file.delete();
    } on FileSystemException {
      // O diretório é temporário; uma eventual limpeza tardia fica a cargo do SO.
    }
  }
}
