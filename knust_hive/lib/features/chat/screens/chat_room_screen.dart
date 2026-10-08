import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:record/record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../../core/services/supabase_service.dart';
import '../chat_attachment.dart';

class ChatRoomScreen extends ConsumerStatefulWidget {
  const ChatRoomScreen({super.key, required this.chatId, required this.title});

  final String chatId;
  final String title;

  @override
  ConsumerState<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends ConsumerState<ChatRoomScreen> {
  static const _bucket = 'chat-media';
  static const _reactions = ['❤️', '😂', '😮', '😢', '🔥', '👍'];
  static const _maxVoiceNoteDuration = Duration(seconds: 90);

  final messageController = TextEditingController();
  final imagePicker = ImagePicker();
  final client = SupabaseService.client;
  final recordedVoiceBytes = BytesBuilder(copy: false);
  AudioRecorder? recorder;
  AudioEncoder? recordingEncoder;
  StreamSubscription<Uint8List>? recorderSubscription;
  Timer? recordingTimer;
  PendingChatAttachment? attachment;
  bool sending = false;
  bool recording = false;
  int recordingSeconds = 0;
  late final Future<Map<String, dynamic>?> chatDetails;
  late final Stream<List<Map<String, dynamic>>> messagesStream;
  late final Stream<List<Map<String, dynamic>>> reactionsStream;

  @override
  void initState() {
    super.initState();
    chatDetails = _loadChatDetails();
    messagesStream = client
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('chat_id', widget.chatId)
        .order('created_at')
        .limit(300);
    reactionsStream = client
        .from('message_reactions')
        .stream(primaryKey: ['id']).eq('chat_id', widget.chatId);
  }

  Future<Map<String, dynamic>?> _loadChatDetails() {
    return client
        .from('chats')
        .select('created_by, is_group')
        .eq('id', widget.chatId)
        .maybeSingle();
  }

  Future<void> _addMember() async {
    try {
      final currentUserId = client.auth.currentUser!.id;
      final memberships = await client
          .from('chat_members')
          .select('user_id')
          .eq('chat_id', widget.chatId);
      final memberIds = memberships.map((row) => row['user_id']).toSet();
      final profiles = await client
          .from('profiles')
          .select('id, display_name, department')
          .neq('id', currentUserId)
          .limit(100);
      final candidates = profiles
          .where((profile) => !memberIds.contains(profile['id']))
          .toList();
      if (!mounted) return;
      if (candidates.isEmpty) {
        _showError('There are no students left to add.');
        return;
      }
      final selected = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (dialogContext) => SimpleDialog(
          title: const Text('Add a student'),
          children: [
            for (final profile in candidates)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(dialogContext, profile),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(profile['display_name'] as String? ?? 'Student'),
                  subtitle: Text(profile['department'] as String? ?? ''),
                ),
              ),
          ],
        ),
      );
      if (selected == null || !mounted) return;
      await client.from('chat_members').insert({
        'chat_id': widget.chatId,
        'user_id': selected['id'],
      });
      if (mounted) _showError('Student added to the group.');
    } catch (error) {
      if (mounted) _showError('Could not add student: $error');
    }
  }

  @override
  void dispose() {
    recordingTimer?.cancel();
    recorderSubscription?.cancel();
    recorder?.dispose();
    messageController.dispose();
    super.dispose();
  }

  Future<void> _chooseAttachment() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            const ListTile(
              title: Text('Share something with your chat'),
              subtitle: Text('Attachments stay private to chat members.'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Photos and videos'),
              onTap: () => Navigator.pop(context, 'media'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(context, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: const Text('Record a video'),
              onTap: () => Navigator.pop(context, 'video'),
            ),
            ListTile(
              leading: const Icon(Icons.graphic_eq),
              title: const Text('Audio'),
              onTap: () => Navigator.pop(context, 'audio'),
            ),
            ListTile(
              leading: const Icon(Icons.attach_file),
              title: const Text('Documents and other files'),
              onTap: () => Navigator.pop(context, 'file'),
            ),
            ListTile(
              leading: const Icon(Icons.location_on_outlined),
              title: const Text('Share current location'),
              onTap: () => Navigator.pop(context, 'location'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;

    if (choice == 'location') {
      await _shareLocation();
      return;
    }
    if (choice == 'camera' || choice == 'video') {
      await _captureMedia(video: choice == 'video');
      return;
    }

    try {
      final picked = await FilePicker.pickFile(
        dialogTitle: choice == 'media'
            ? 'Choose a photo or video'
            : choice == 'audio'
                ? 'Choose an audio file'
                : 'Choose a document',
        type: switch (choice) {
          'media' => FileType.media,
          'audio' => FileType.audio,
          _ => FileType.custom,
        },
        allowedExtensions:
            choice == 'file' ? ChatAttachment.supportedExtensions : null,
      );
      if (picked == null || !mounted) return;
      final fileSize = await picked.length();
      if (fileSize != null && fileSize > ChatAttachment.maxBytes) {
        _showError('Files must be 25 MB or smaller.');
        return;
      }
      final bytes = await picked.readAsBytes();
      _setAttachment(picked.name, bytes, null);
    } catch (error) {
      if (mounted) _showError('Could not choose that file: $error');
    }
  }

  void _setAttachment(String fileName, Uint8List bytes, String? detectedMime) {
    if (bytes.isEmpty) {
      _showError('The selected file is empty.');
      return;
    }
    if (bytes.length > ChatAttachment.maxBytes) {
      _showError('Files must be 25 MB or smaller.');
      return;
    }
    final mimeType = ChatAttachment.normalizeMimeType(fileName, detectedMime);
    if (mimeType == null || ChatAttachment.kindFor(mimeType) == null) {
      _showError('That file type is not supported in chat.');
      return;
    }
    setState(() {
      attachment = PendingChatAttachment(
        name: fileName,
        bytes: bytes,
        mimeType: mimeType,
      );
    });
  }

  Future<void> _captureMedia({required bool video}) async {
    try {
      final file = video
          ? await imagePicker.pickVideo(
              source: ImageSource.camera,
              maxDuration: const Duration(minutes: 1),
            )
          : await imagePicker.pickImage(
              source: ImageSource.camera,
              maxWidth: 2048,
              maxHeight: 2048,
              imageQuality: 85,
            );
      if (file == null || !mounted) return;
      if (await file.length() > ChatAttachment.maxBytes) {
        _showError('Files must be 25 MB or smaller.');
        return;
      }
      _setAttachment(file.name, await file.readAsBytes(), file.mimeType);
    } catch (error) {
      if (mounted) _showError('Could not open the camera: $error');
    }
  }

  Future<void> _toggleVoiceRecording() async {
    if (recording) {
      await _finishVoiceRecording();
      return;
    }
    if (sending || attachment != null) return;

    final audioRecorder = AudioRecorder();
    try {
      if (!await audioRecorder.hasPermission()) {
        await audioRecorder.dispose();
        if (mounted) _showError('Microphone permission is needed to record.');
        return;
      }
      AudioEncoder? encoder;
      final candidates = kIsWeb
          ? [AudioEncoder.opus, AudioEncoder.aacLc, AudioEncoder.wav]
          : [AudioEncoder.aacLc, AudioEncoder.opus, AudioEncoder.wav];
      for (final candidate in candidates) {
        if (await audioRecorder.isEncoderSupported(candidate)) {
          encoder = candidate;
          break;
        }
      }
      if (encoder == null) {
        await audioRecorder.dispose();
        if (mounted) {
          _showError('Voice recording is not supported on this device.');
        }
        return;
      }

      recordedVoiceBytes.clear();
      final stream = await audioRecorder.startStream(
        RecordConfig(encoder: encoder, sampleRate: 48000, numChannels: 1),
      );
      recorder = audioRecorder;
      recordingEncoder = encoder;
      recorderSubscription = stream.listen(
        (chunk) {
          recordedVoiceBytes.add(chunk);
          if (recordedVoiceBytes.length > ChatAttachment.maxBytes) {
            _cancelVoiceRecording(
              'Voice note reached the 25 MB upload limit.',
            );
          }
        },
        onError: (Object error) {
          if (mounted) _showError('Voice recording failed: $error');
        },
      );
      setState(() {
        recording = true;
        recordingSeconds = 0;
      });
      recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) return;
        if (recordingSeconds >= _maxVoiceNoteDuration.inSeconds) {
          _finishVoiceRecording();
          return;
        }
        setState(() => recordingSeconds++);
      });
    } catch (error) {
      await audioRecorder.dispose();
      if (mounted) _showError('Could not start voice recording: $error');
    }
  }

  Future<void> _finishVoiceRecording() async {
    final activeRecorder = recorder;
    recordingTimer?.cancel();
    recordingTimer = null;
    if (activeRecorder == null) return;
    try {
      await activeRecorder.stop();
      await recorderSubscription?.cancel();
      recorderSubscription = null;
      final bytes = recordedVoiceBytes.takeBytes();
      final encoder = recordingEncoder;
      final extension = switch (encoder) {
        AudioEncoder.opus => kIsWeb ? 'webm' : 'ogg',
        AudioEncoder.aacLc => 'm4a',
        _ => 'wav',
      };
      final mimeType = switch (encoder) {
        AudioEncoder.opus => kIsWeb ? 'audio/webm' : 'audio/ogg',
        AudioEncoder.aacLc => 'audio/mp4',
        _ => 'audio/wav',
      };
      final fileName =
          'voice-note-${DateTime.now().millisecondsSinceEpoch}.$extension';
      recorder = null;
      recordingEncoder = null;
      await activeRecorder.dispose();
      if (!mounted) return;
      setState(() => recording = false);
      _setAttachment(fileName, bytes, mimeType);
    } catch (error) {
      await activeRecorder.dispose();
      recorder = null;
      recordingEncoder = null;
      if (mounted) {
        setState(() => recording = false);
        _showError('Could not finish voice recording: $error');
      }
    }
  }

  Future<void> _cancelVoiceRecording(String message) async {
    recordingTimer?.cancel();
    recordingTimer = null;
    final activeRecorder = recorder;
    recorder = null;
    await recorderSubscription?.cancel();
    recorderSubscription = null;
    if (activeRecorder != null) {
      await activeRecorder.cancel();
      await activeRecorder.dispose();
    }
    if (!mounted) return;
    setState(() => recording = false);
    _showError(message);
  }

  Future<void> _shareLocation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Share your current location?'),
        content: const Text(
          'Your location will be sent as a map link and remain in this chat. '
          'Only share it with people you trust.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Share location'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _showError('Turn on location services to share your location.');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _showError('Location permission was not granted.');
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.medium),
      );
      messageController.text =
          '${messageController.text.trim().isEmpty ? '' : '${messageController.text.trim()}\n'}'
          '📍 My current location: https://maps.google.com/?q=${position.latitude},${position.longitude}';
      await _send();
    } catch (error) {
      if (mounted) _showError('Could not get your current location: $error');
    }
  }

  Future<void> _send() async {
    final text = messageController.text.trim();
    final picked = attachment;
    if ((text.isEmpty && picked == null) || sending) return;

    setState(() => sending = true);
    String? uploadedPath;
    try {
      String? mimeType;
      String? messageType;
      String? fileName;

      if (picked != null) {
        final bytes = picked.bytes;
        mimeType = picked.mimeType;
        final kind = ChatAttachment.kindFor(mimeType);
        if (kind == null) {
          throw const FormatException(
              'That file type is not supported in chat.');
        }

        final extension = picked.name.contains('.')
            ? picked.name.split('.').last.toLowerCase()
            : 'bin';
        final safeExtension = extension.replaceAll(
          RegExp(r'[^a-z0-9]'),
          '',
        );
        final safeName =
            picked.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
        fileName = safeName.length <= 120
            ? safeName
            : safeName.substring(safeName.length - 120);
        messageType = kind.name;
        uploadedPath =
            '${widget.chatId}/${client.auth.currentUser!.id}/${const Uuid().v4()}.$safeExtension';

        await client.storage.from(_bucket).uploadBinary(
              uploadedPath,
              bytes,
              fileOptions: FileOptions(contentType: mimeType, upsert: false),
            );
      }

      await client.from('messages').insert({
        'id': const Uuid().v4(),
        'chat_id': widget.chatId,
        'sender_id': client.auth.currentUser!.id,
        'text': text,
        'message_type': messageType ?? 'text',
        'attachment_path': uploadedPath,
        'file_name': fileName,
        'mime_type': mimeType,
      });
      messageController.clear();
      if (mounted) setState(() => attachment = null);
    } on PostgrestException catch (error) {
      await _cleanupFailedUpload(uploadedPath);
      if (mounted) _showError(error.message);
    } catch (error) {
      await _cleanupFailedUpload(uploadedPath);
      if (mounted) _showError('Could not send message: $error');
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> _cleanupFailedUpload(String? path) async {
    if (path == null) return;
    try {
      await client.storage.from(_bucket).remove([path]);
    } catch (error) {
      if (mounted) {
        _showError(
            'The message failed and its uploaded file could not be removed: $error');
      }
    }
  }

  Future<void> _toggleReaction(
    Map<String, dynamic> message,
    String emoji,
  ) async {
    final messageId = message['id'] as String;
    final userId = client.auth.currentUser!.id;
    try {
      final existing = await client
          .from('message_reactions')
          .select('id')
          .eq('message_id', messageId)
          .eq('user_id', userId)
          .eq('emoji', emoji)
          .maybeSingle();
      if (existing == null) {
        await client.from('message_reactions').insert({
          'message_id': messageId,
          'chat_id': widget.chatId,
          'user_id': userId,
          'emoji': emoji,
        });
      } else {
        await client
            .from('message_reactions')
            .delete()
            .eq('id', existing['id']);
      }
    } catch (error) {
      if (mounted) _showError('Could not update reaction: $error');
    }
  }

  Future<void> _deleteMessage(Map<String, dynamic> message) async {
    final path = message['attachment_path'] as String?;
    try {
      await client.from('messages').delete().eq('id', message['id']);
    } catch (error) {
      if (mounted) _showError('Could not delete message: $error');
      return;
    }
    if (path == null) {
      return;
    }
    try {
      await client.storage.from(_bucket).remove([path]);
    } catch (error) {
      if (mounted) {
        _showError(
            'Message deleted, but its file could not be removed: $error');
      }
    }
  }

  Future<void> _showReactionPicker(Map<String, dynamic> message) async {
    final emoji = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final reaction in _reactions)
                IconButton(
                  tooltip: reaction,
                  iconSize: 30,
                  onPressed: () => Navigator.pop(context, reaction),
                  icon: Text(reaction),
                ),
            ],
          ),
        ),
      ),
    );
    if (emoji != null) await _toggleReaction(message, emoji);
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = client.auth.currentUser!.id;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          FutureBuilder<Map<String, dynamic>?>(
            future: chatDetails,
            builder: (context, snapshot) {
              final chat = snapshot.data;
              if (chat?['is_group'] != true ||
                  chat?['created_by'] != currentUserId) {
                return const SizedBox.shrink();
              }
              return IconButton(
                tooltip: 'Add student',
                onPressed: _addMember,
                icon: const Icon(Icons.person_add_alt_1),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: messagesStream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text('Could not load messages: ${snapshot.error}'),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final messages = snapshot.data!;
                if (messages.isEmpty) {
                  return const _ChatEmptyState();
                }
                return StreamBuilder<List<Map<String, dynamic>>>(
                  stream: reactionsStream,
                  builder: (context, reactionSnapshot) {
                    final reactions = reactionSnapshot.data ?? const [];
                    return ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final message = messages[messages.length - index - 1];
                        final own = message['sender_id'] == currentUserId;
                        final messageReactions = reactions
                            .where((reaction) =>
                                reaction['message_id'] == message['id'])
                            .toList();
                        return _ChatMessageBubble(
                          key: ValueKey<String>(message['id'] as String),
                          message: message,
                          own: own,
                          reactions: messageReactions,
                          currentUserId: currentUserId,
                          onReact: () => _showReactionPicker(message),
                          onToggleReaction: (emoji) =>
                              _toggleReaction(message, emoji),
                          onDelete: () => _deleteMessage(message),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
          _buildComposer(context),
        ],
      ),
    );
  }

  Widget _buildComposer(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border(top: BorderSide(color: colors.outlineVariant)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (attachment case final selected?)
              _AttachmentDraft(
                file: selected,
                onRemove:
                    sending ? null : () => setState(() => attachment = null),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton.filledTonal(
                  tooltip: 'Add a photo, video, audio or file',
                  onPressed: sending || recording ? null : _chooseAttachment,
                  icon: const Icon(Icons.add),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: messageController,
                    readOnly: sending || recording,
                    maxLength: 2000,
                    minLines: 1,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: recording
                          ? 'Recording voice note…'
                          : attachment == null
                              ? 'Send a message'
                              : 'Add a caption',
                      counterText: '',
                      filled: true,
                      fillColor: colors.surfaceContainerHighest,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: recording ? 'Stop recording' : 'Record a voice note',
                  onPressed: sending ? null : _toggleVoiceRecording,
                  icon: Icon(
                    recording ? Icons.stop_circle_outlined : Icons.mic_none,
                    color: recording ? colors.error : null,
                  ),
                ),
                const SizedBox(width: 4),
                IconButton.filled(
                  tooltip: sending
                      ? 'Sending'
                      : recording
                          ? 'Stop the recording before sending'
                          : 'Send',
                  onPressed: sending || recording ? null : _send,
                  icon: sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          attachment == null
                              ? Icons.send_rounded
                              : Icons.arrow_upward,
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatEmptyState extends StatelessWidget {
  const _ChatEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chat_bubble_outline_rounded,
              size: 52,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text('Your space, your people',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Send a message, share a photo, or drop a voice note from your device.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatMessageBubble extends StatelessWidget {
  const _ChatMessageBubble({
    super.key,
    required this.message,
    required this.own,
    required this.reactions,
    required this.currentUserId,
    required this.onReact,
    required this.onToggleReaction,
    required this.onDelete,
  });

  final Map<String, dynamic> message;
  final bool own;
  final List<Map<String, dynamic>> reactions;
  final String currentUserId;
  final VoidCallback onReact;
  final ValueChanged<String> onToggleReaction;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = message['text'] as String? ?? '';
    final path = message['attachment_path'] as String?;
    final messageType = message['message_type'] as String? ?? 'text';
    final bubbleColor = own ? colors.primary : colors.surfaceContainerHighest;
    final foreground = own ? colors.onPrimary : colors.onSurface;
    final time = DateTime.tryParse(message['created_at'] as String? ?? '');

    return Align(
      alignment: own ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.82,
          minWidth: 76,
        ),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment:
                own ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onLongPress: onReact,
                child: Container(
                  padding: EdgeInsets.all(path == null ? 12 : 8),
                  decoration: BoxDecoration(
                    color: bubbleColor,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: Radius.circular(own ? 18 : 5),
                      bottomRight: Radius.circular(own ? 5 : 18),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (path != null)
                        _AttachmentPreview(
                          path: path,
                          fileName: message['file_name'] as String? ??
                              'Shared attachment',
                          mimeType: message['mime_type'] as String?,
                          messageType: messageType,
                        ),
                      if (text.isNotEmpty) ...[
                        if (path != null) const SizedBox(height: 8),
                        Text(
                          text,
                          style: TextStyle(color: foreground, height: 1.35),
                        ),
                      ],
                      if (time != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          DateFormat('h:mm a').format(time.toLocal()),
                          style: TextStyle(
                            color: foreground.withValues(alpha: 0.68),
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (reactions.isNotEmpty)
                    Wrap(
                      spacing: 4,
                      children: _reactionCounts(reactions).entries.map((entry) {
                        final selected = reactions.any((reaction) =>
                            reaction['user_id'] == currentUserId &&
                            reaction['emoji'] == entry.key);
                        return ActionChip(
                          visualDensity: VisualDensity.compact,
                          avatar: Text(entry.key,
                              style: const TextStyle(fontSize: 15)),
                          label: Text('${entry.value}'),
                          onPressed: () => onToggleReaction(entry.key),
                          backgroundColor: selected
                              ? colors.secondaryContainer
                              : colors.surface,
                          side: BorderSide(color: colors.outlineVariant),
                        );
                      }).toList(),
                    ),
                  IconButton(
                    tooltip: 'React to message',
                    visualDensity: VisualDensity.compact,
                    iconSize: 17,
                    onPressed: onReact,
                    icon: const Icon(Icons.add_reaction_outlined),
                  ),
                  if (own)
                    PopupMenuButton<String>(
                      tooltip: 'Message options',
                      padding: EdgeInsets.zero,
                      iconSize: 17,
                      onSelected: (choice) {
                        if (choice == 'delete') onDelete();
                        if (choice == 'react') onReact();
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: 'react',
                          child: Text('Add a reaction'),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text('Delete for everyone'),
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Map<String, int> _reactionCounts(List<Map<String, dynamic>> reactions) {
    final counts = <String, int>{};
    for (final reaction in reactions) {
      final emoji = reaction['emoji'] as String;
      counts.update(emoji, (count) => count + 1, ifAbsent: () => 1);
    }
    return counts;
  }
}

class PendingChatAttachment {
  const PendingChatAttachment({
    required this.name,
    required this.bytes,
    required this.mimeType,
  });

  final String name;
  final Uint8List bytes;
  final String mimeType;
}

class _AttachmentDraft extends StatelessWidget {
  const _AttachmentDraft({required this.file, required this.onRemove});

  final PendingChatAttachment file;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final kind = ChatAttachment.kindFor(file.mimeType);
    final icon = switch (kind) {
      ChatAttachmentKind.image => Icons.image_outlined,
      ChatAttachmentKind.video => Icons.video_file_outlined,
      ChatAttachmentKind.audio => Icons.audio_file_outlined,
      _ => Icons.insert_drive_file_outlined,
    };
    return ListTile(
      dense: true,
      leading: Icon(icon),
      title: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('${file.bytes.lengthInBytes ~/ 1024} KB · ready to send'),
      trailing: IconButton(
        tooltip: 'Remove attachment',
        onPressed: onRemove,
        icon: const Icon(Icons.close),
      ),
    );
  }
}

class _AttachmentPreview extends StatefulWidget {
  const _AttachmentPreview({
    required this.path,
    required this.fileName,
    required this.mimeType,
    required this.messageType,
  });

  final String path;
  final String fileName;
  final String? mimeType;
  final String messageType;

  @override
  State<_AttachmentPreview> createState() => _AttachmentPreviewState();
}

class _AttachmentPreviewState extends State<_AttachmentPreview> {
  late Future<String> signedUrl;

  @override
  void initState() {
    super.initState();
    signedUrl = _createSignedUrl();
  }

  Future<String> _createSignedUrl() => SupabaseService.client.storage
      .from('chat-media')
      .createSignedUrl(widget.path, 60 * 60);

  @override
  Widget build(BuildContext context) {
    final type = widget.messageType;
    if (type != 'image') {
      final icon = switch (type) {
        'video' => Icons.play_circle_outline,
        'audio' => Icons.graphic_eq,
        _ => Icons.insert_drive_file_outlined,
      };
      return FutureBuilder<String>(
        future: signedUrl,
        builder: (context, snapshot) => SizedBox(
          width: 240,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(icon, size: 30),
            title: Text(
              widget.fileName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              snapshot.hasError
                  ? 'Could not load attachment'
                  : snapshot.hasData
                      ? 'Tap to open'
                      : 'Loading attachment…',
            ),
            onTap: snapshot.hasData
                ? () => launchUrl(
                      Uri.parse(snapshot.data!),
                      mode: LaunchMode.externalApplication,
                    )
                : null,
          ),
        ),
      );
    }

    return FutureBuilder<String>(
      future: signedUrl,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const SizedBox(
            width: 240,
            height: 100,
            child: Center(child: Text('Could not load photo')),
          );
        }
        if (!snapshot.hasData) {
          return const SizedBox(
            width: 240,
            height: 150,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return GestureDetector(
          onTap: () => showDialog<void>(
            context: context,
            builder: (context) => Dialog.fullscreen(
              child: Stack(
                children: [
                  Center(
                    child: InteractiveViewer(
                      child: Image.network(snapshot.data!, fit: BoxFit.contain),
                    ),
                  ),
                  Positioned(
                    top: 24,
                    right: 16,
                    child: IconButton.filled(
                      tooltip: 'Close photo',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ),
                ],
              ),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.network(
              snapshot.data!,
              width: 250,
              height: 250,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => const SizedBox(
                width: 250,
                height: 120,
                child: Center(child: Text('Photo unavailable')),
              ),
            ),
          ),
        );
      },
    );
  }
}
