String hopeAudioFileExtension(String contentType) {
  final mimeType = contentType.split(';').first.trim().toLowerCase();
  return switch (mimeType) {
    'audio/mpeg' || 'audio/mp3' => 'mp3',
    'audio/wav' || 'audio/x-wav' => 'wav',
    'audio/mp4' || 'audio/aac' => 'm4a',
    'audio/ogg' => 'ogg',
    _ => 'mp3',
  };
}
