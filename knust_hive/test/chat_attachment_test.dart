import 'package:flutter_test/flutter_test.dart';
import 'package:knust_hive/features/chat/chat_attachment.dart';

void main() {
  group('ChatAttachment', () {
    test('recognizes image, video, audio and document types', () {
      expect(
        ChatAttachment.kindFor('image/jpeg'),
        ChatAttachmentKind.image,
      );
      expect(
        ChatAttachment.kindFor('video/mp4'),
        ChatAttachmentKind.video,
      );
      expect(
        ChatAttachment.kindFor('audio/mpeg'),
        ChatAttachmentKind.audio,
      );
      expect(
        ChatAttachment.kindFor('application/pdf'),
        ChatAttachmentKind.file,
      );
      expect(ChatAttachment.kindFor('application/octet-stream'), isNull);
      expect(ChatAttachment.kindFor('application/x-executable'), isNull);
    });

    test('normalizes a supported file using its extension', () {
      expect(
        ChatAttachment.normalizeMimeType('course-notes.PDF', null),
        'application/pdf',
      );
      expect(
        ChatAttachment.normalizeMimeType('lecture.mov', null),
        'video/quicktime',
      );
      expect(ChatAttachment.normalizeMimeType('program.exe', null), isNull);
    });

    test('limits uploads to 25 MiB', () {
      expect(ChatAttachment.maxBytes, 25 * 1024 * 1024);
      expect(ChatAttachment.supportedExtensions, contains('mp4'));
      expect(ChatAttachment.supportedExtensions, contains('docx'));
      expect(ChatAttachment.supportedExtensions, contains('m4a'));
    });
  });
}
