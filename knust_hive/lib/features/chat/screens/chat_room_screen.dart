import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/services/supabase_service.dart';

class ChatRoomScreen extends ConsumerStatefulWidget {
  const ChatRoomScreen({super.key, required this.chatId, required this.title});

  final String chatId;
  final String title;

  @override
  ConsumerState<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends ConsumerState<ChatRoomScreen> {
  final messageController = TextEditingController();
  bool sending = false;
  late Future<Map<String, dynamic>?> chatDetails;

  @override
  void initState() {
    super.initState();
    chatDetails = _loadChatDetails();
  }

  Future<Map<String, dynamic>?> _loadChatDetails() {
    return SupabaseService.client
        .from('chats')
        .select('created_by, is_group')
        .eq('id', widget.chatId)
        .maybeSingle();
  }

  Future<void> _addMember() async {
    final client = SupabaseService.client;
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
    messageController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = messageController.text.trim();
    if (text.isEmpty || sending) return;
    setState(() => sending = true);
    try {
      await SupabaseService.client.from('messages').insert({
        'id': const Uuid().v4(),
        'chat_id': widget.chatId,
        'sender_id': SupabaseService.client.auth.currentUser!.id,
        'text': text,
      });
      messageController.clear();
    } on PostgrestException catch (error) {
      _showError(error.message);
    } catch (error) {
      _showError('Could not send message: $error');
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = SupabaseService.client.auth.currentUser!.id;
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
              stream: SupabaseService.client
                  .from('messages')
                  .stream(primaryKey: ['id'])
                  .eq('chat_id', widget.chatId)
                  .order('created_at')
                  .limit(300),
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
                  return const Center(child: Text('Say hello to get started.'));
                }
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[messages.length - index - 1];
                    final own = message['sender_id'] == currentUserId;
                    return Align(
                      alignment:
                          own ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
                        ),
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: own
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.surfaceContainer,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          message['text'] as String? ?? '',
                          style: TextStyle(
                            color: own
                                ? Theme.of(context).colorScheme.onPrimary
                                : null,
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: messageController,
                      maxLength: 2000,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: 'Message',
                        counterText: '',
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: 'Send message',
                    onPressed: sending ? null : _send,
                    icon: sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
