import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/supabase_service.dart';

class ChatListScreen extends ConsumerStatefulWidget {
  const ChatListScreen({super.key});

  @override
  ConsumerState<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends ConsumerState<ChatListScreen> {
  late Future<List<Map<String, dynamic>>> conversations;

  @override
  void initState() {
    super.initState();
    conversations = _loadConversations();
  }

  Future<List<Map<String, dynamic>>> _loadConversations() async {
    final client = SupabaseService.client;
    final userId = client.auth.currentUser!.id;
    final rows = await client
        .from('chat_members')
        .select('chat_id, chats(id, name, is_group, created_at)')
        .eq('user_id', userId);
    final conversations = rows
        .map((row) => row['chats'])
        .whereType<Map<String, dynamic>>()
        .toList();
    for (final chat
        in conversations.where((chat) => chat['is_group'] != true)) {
      final otherMembership = await client
          .from('chat_members')
          .select('user_id')
          .eq('chat_id', chat['id'])
          .neq('user_id', userId)
          .maybeSingle();
      if (otherMembership == null) continue;
      final otherProfile = await client
          .from('profiles')
          .select('display_name')
          .eq('id', otherMembership['user_id'])
          .maybeSingle();
      chat['name'] = otherProfile?['display_name'] ?? 'Direct message';
    }
    return conversations;
  }

  Future<void> _refresh() async {
    setState(() => conversations = _loadConversations());
    await conversations;
  }

  Future<void> _createGroup() async {
    final nameController = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create a group chat'),
        content: TextField(
          controller: nameController,
          autofocus: true,
          maxLength: 60,
          decoration: const InputDecoration(labelText: 'Group name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, nameController.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    nameController.dispose();
    if (name == null || name.isEmpty || !mounted) return;

    try {
      final client = SupabaseService.client;
      final userId = client.auth.currentUser!.id;
      final chat = await client
          .from('chats')
          .insert({
            'name': name,
            'is_group': true,
            'created_by': userId,
          })
          .select('id')
          .single();
      await client.from('chat_members').insert({
        'chat_id': chat['id'],
        'user_id': userId,
      });
      if (!mounted) return;
      await context
          .push('/chat/${chat['id']}?title=${Uri.encodeQueryComponent(name)}');
      if (mounted) _refresh();
    } catch (error) {
      _showError('Could not create group chat: $error');
    }
  }

  Future<void> _startDirectChat() async {
    try {
      final client = SupabaseService.client;
      final profiles = await client
          .from('profiles')
          .select('id, display_name, department')
          .neq('id', client.auth.currentUser!.id)
          .order('display_name')
          .limit(100);
      if (!mounted) return;
      if (profiles.isEmpty) {
        _showError('No other student profiles are available yet.');
        return;
      }
      final selected = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (dialogContext) => SimpleDialog(
          title: const Text('Message a student'),
          children: [
            for (final student in profiles)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(dialogContext, student),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(student['display_name'] as String? ?? 'Student'),
                  subtitle: Text(student['department'] as String? ?? ''),
                ),
              ),
          ],
        ),
      );
      if (selected == null || !mounted) return;
      final chatId = await client.rpc(
        'create_direct_chat',
        params: {'target_user': selected['id']},
      );
      final title = selected['display_name'] as String? ?? 'Direct message';
      if (!mounted) return;
      await context
          .push('/chat/$chatId?title=${Uri.encodeQueryComponent(title)}');
      if (mounted) await _refresh();
    } catch (error) {
      if (mounted) _showError('Could not start direct chat: $error');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Start a conversation',
            onSelected: (action) {
              if (action == 'group') _createGroup();
              if (action == 'direct') _startDirectChat();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'direct',
                child: ListTile(
                  leading: Icon(Icons.person_outline),
                  title: Text('Message a student'),
                ),
              ),
              PopupMenuItem(
                value: 'group',
                child: ListTile(
                  leading: Icon(Icons.groups_outlined),
                  title: Text('Create group chat'),
                ),
              ),
            ],
            icon: const Icon(Icons.add_comment_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    colors.primary,
                    colors.primary.withValues(alpha: 0.82)
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.forum_rounded,
                      color: Colors.white, size: 28),
                  const SizedBox(height: 12),
                  Text(
                    'Your campus circle',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Keep up with your people. Share photos, clips, voice notes and files.',
                    style: TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _startDirectChat,
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: colors.primary,
                          ),
                          icon: const Icon(Icons.chat_bubble_outline),
                          label: const Text('Message'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _createGroup,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white70),
                          ),
                          icon: const Icon(Icons.group_add_outlined),
                          label: const Text('New group'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: conversations,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return ListView(
                      children: [
                        const SizedBox(height: 120),
                        Center(
                            child: Text(
                                'Could not load chats: ${snapshot.error}')),
                        Center(
                          child: TextButton(
                            onPressed: _refresh,
                            child: const Text('Try again'),
                          ),
                        ),
                      ],
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final chats = snapshot.data!;
                  if (chats.isEmpty) {
                    return ListView(
                      children: const [
                        SizedBox(height: 120),
                        Icon(Icons.forum_outlined, size: 44),
                        SizedBox(height: 12),
                        Center(child: Text('No chats yet')),
                        Center(
                          child:
                              Text('Create a group to start a conversation.'),
                        ),
                      ],
                    );
                  }
                  return ListView.builder(
                    itemCount: chats.length,
                    itemBuilder: (context, index) {
                      final chat = chats[index];
                      final id = chat['id'] as String;
                      final title = chat['name'] as String? ?? 'Conversation';
                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 5,
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: colors.secondaryContainer,
                            child: Icon(
                              chat['is_group'] == true
                                  ? Icons.groups_rounded
                                  : Icons.person_rounded,
                              color: colors.primary,
                            ),
                          ),
                          title: Text(title,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: const Text('Open conversation'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => context.push(
                            '/chat/$id?title=${Uri.encodeQueryComponent(title)}',
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
