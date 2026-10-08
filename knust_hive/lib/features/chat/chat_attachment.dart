enum ChatAttachmentKind { image, video, audio, file }

class ChatAttachment {
  const ChatAttachment._();

  static const maxBytes = 25 * 1024 * 1024;

  static const supportedExtensions = [
    'jpg',
    'jpeg',
    'png',
    'gif',
    'webp',
    'mp4',
    'webm',
    'mov',
    'mp3',
    'm4a',
    'opus',
    'ogg',
    'wav',
    'pdf',
    'txt',
    'csv',
    'rtf',
    'zip',
    'doc',
    'docx',
    'xls',
    'xlsx',
    'ppt',
    'pptx',
  ];

  static const _mimeTypes = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'gif': 'image/gif',
    'webp': 'image/webp',
    'mp4': 'video/mp4',
    'webm': 'video/webm',
    'mov': 'video/quicktime',
    'mp3': 'audio/mpeg',
    'm4a': 'audio/mp4',
    'opus': 'audio/ogg',
    'ogg': 'audio/ogg',
    'wav': 'audio/wav',
    'pdf': 'application/pdf',
    'txt': 'text/plain',
    'csv': 'text/csv',
    'rtf': 'application/rtf',
    'zip': 'application/zip',
    'doc': 'application/msword',
    'docx':
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls': 'application/vnd.ms-excel',
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'ppt': 'application/vnd.ms-powerpoint',
    'pptx':
        'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  };

  static String? mimeTypeForName(String fileName) {
    final extension = fileName.split('.').last.toLowerCase();
    return _mimeTypes[extension];
  }

  static ChatAttachmentKind? kindFor(String mimeType) {
    if (!_mimeTypes.values.contains(mimeType) && mimeType != 'audio/webm') {
      return null;
    }
    if (mimeType.startsWith('image/')) return ChatAttachmentKind.image;
    if (mimeType.startsWith('video/')) return ChatAttachmentKind.video;
    if (mimeType.startsWith('audio/')) return ChatAttachmentKind.audio;
    if (mimeType.startsWith('application/') || mimeType.startsWith('text/')) {
      return ChatAttachmentKind.file;
    }
    return null;
  }

  static String? normalizeMimeType(String fileName, String? detectedMimeType) {
    final detected = detectedMimeType?.toLowerCase();
    if (detected != null &&
        (_mimeTypes.values.contains(detected) ||
            (detected == 'audio/webm' &&
                fileName.toLowerCase().endsWith('.webm')))) {
      return detected;
    }
    return mimeTypeForName(fileName);
  }
}
