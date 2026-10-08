import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/models.dart';
import '../providers/feed_provider.dart';

class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen> {
  FeedCategory? filter;

  @override
  Widget build(BuildContext context) {
    final feedAsync = ref.watch(feedProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Campus feed')),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.gold,
        foregroundColor: AppColors.forest,
        onPressed: () => _openComposer(context),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                _Chip(
                    label: 'All',
                    selected: filter == null,
                    onTap: () => setState(() => filter = null)),
                ...FeedCategory.values.map((c) => Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: _Chip(
                        label: _label(c),
                        selected: filter == c,
                        onTap: () => setState(() => filter = c),
                      ),
                    )),
              ]),
            ),
          ),
          Expanded(
            child: feedAsync.when(
              data: (posts) {
                final visible = filter == null
                    ? posts
                    : posts.where((p) => p.category == filter).toList();
                if (visible.isEmpty) {
                  return const Center(
                      child: Text('Nothing here yet. Be the first to post.',
                          style: TextStyle(color: Color(0xFF5B6355))));
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: visible.length,
                  itemBuilder: (ctx, i) => _PostCard(post: visible[i]),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Couldn\'t load feed: $e')),
            ),
          ),
        ],
      ),
    );
  }

  String _label(FeedCategory c) => switch (c) {
        FeedCategory.event => 'Event',
        FeedCategory.lostFound => 'Lost & Found',
        FeedCategory.shoutout => 'Shoutout',
        FeedCategory.studyGroup => 'Study Group',
      };

  void _openComposer(BuildContext context) {
    FeedCategory cat = FeedCategory.event;
    final textCtrl = TextEditingController();
    var posting = false;
    String? submitError;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16),
        child: StatefulBuilder(
          builder: (ctx, setSheetState) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('New post', style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                children: FeedCategory.values
                    .map((c) => ChoiceChip(
                          label: Text(_label(c)),
                          selected: cat == c,
                          onSelected: posting
                              ? null
                              : (_) => setSheetState(() => cat = c),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: textCtrl,
                maxLength: 1000,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: "What's happening?",
                  alignLabelWithHint: true,
                ),
              ),
              if (submitError != null)
                Text(
                  submitError!,
                  style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: posting
                      ? null
                      : () async {
                          final text = textCtrl.text.trim();
                          if (text.isEmpty) {
                            setSheetState(
                              () => submitError = 'Write something first.',
                            );
                            return;
                          }
                          setSheetState(() {
                            posting = true;
                            submitError = null;
                          });
                          try {
                            await ref.read(feedActionsProvider).post(
                                  category: cat,
                                  text: text,
                                );
                            if (ctx.mounted) Navigator.pop(ctx);
                          } catch (error) {
                            if (ctx.mounted) {
                              setSheetState(() {
                                submitError = 'Could not publish: $error';
                                posting = false;
                              });
                            }
                          }
                        },
                  child: posting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Post'),
                ),
              ),
            ],
          ),
        ),
      ),
    ).whenComplete(textCtrl.dispose);
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Chip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
        label: Text(label), selected: selected, onSelected: (_) => onTap());
  }
}

class _PostCard extends ConsumerWidget {
  final FeedPost post;
  const _PostCard({required this.post});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mins = DateTime.now().difference(post.ts).inMinutes;
    final isOwner =
        SupabaseService.client.auth.currentUser?.id == post.postedBy;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _categoryLabel(post.category),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.forest,
                  ),
                ),
                if (isOwner)
                  IconButton(
                    tooltip: 'Delete post',
                    icon: const Icon(Icons.delete_outline, size: 18),
                    onPressed: () async {
                      try {
                        await ref.read(feedActionsProvider).delete(post.id);
                      } catch (error) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text('Could not delete post: $error')),
                          );
                        }
                      }
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  )
                else
                  IconButton(
                    tooltip: 'Report post',
                    icon: const Icon(Icons.flag_outlined, size: 18),
                    onPressed: () =>
                        _reportContent(context, post.id, 'feed_post'),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(post.text, style: const TextStyle(fontSize: 13.5)),
            if (post.category == FeedCategory.event) ...[
              const SizedBox(height: 8),
              _RsvpButton(postId: post.id),
            ],
            const SizedBox(height: 6),
            Text(
              mins < 1 ? 'just now' : '${mins}m ago',
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF5B6355),
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _categoryLabel(FeedCategory category) => switch (category) {
        FeedCategory.event => 'Event',
        FeedCategory.lostFound => 'Lost & Found',
        FeedCategory.shoutout => 'Shoutout',
        FeedCategory.studyGroup => 'Study Group',
      };

  Future<void> _reportContent(
      BuildContext context, String contentId, String contentType) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Why are you reporting this?'),
        children: [
          for (final reason in const [
            'Spam or misleading',
            'Harassment or hate',
            'Unsafe content',
            'Other',
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, reason),
              child: Text(reason),
            ),
        ],
      ),
    );
    if (reason == null || !context.mounted) return;
    try {
      await SupabaseService.client.from('moderation_reports').insert({
        'reporter_id': SupabaseService.client.auth.currentUser!.id,
        'content_type': contentType,
        'content_id': contentId,
        'reason': reason,
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Report sent to moderators.')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not send report: $error')),
        );
      }
    }
  }
}

class _RsvpButton extends StatefulWidget {
  const _RsvpButton({required this.postId});

  final String postId;

  @override
  State<_RsvpButton> createState() => _RsvpButtonState();
}

class _RsvpButtonState extends State<_RsvpButton> {
  late Future<bool> _membership;
  bool _updating = false;

  @override
  void initState() {
    super.initState();
    _membership = _loadMembership();
  }

  Future<bool> _loadMembership() async {
    final client = SupabaseService.client;
    final userId = client.auth.currentUser!.id;
    final row = await client
        .from('event_rsvps')
        .select('user_id')
        .eq('post_id', widget.postId)
        .eq('user_id', userId)
        .maybeSingle();
    return row != null;
  }

  Future<void> _toggle(bool isGoing) async {
    setState(() => _updating = true);
    final client = SupabaseService.client;
    try {
      final userId = client.auth.currentUser!.id;
      if (isGoing) {
        await client
            .from('event_rsvps')
            .delete()
            .eq('post_id', widget.postId)
            .eq('user_id', userId);
      } else {
        await client.from('event_rsvps').insert({
          'post_id': widget.postId,
          'user_id': userId,
        });
      }
      if (mounted) setState(() => _membership = _loadMembership());
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update RSVP: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
        future: _membership,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Text(
              'RSVP unavailable: ${snapshot.error}',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            );
          }
          if (!snapshot.hasData) {
            return const LinearProgressIndicator();
          }
          final isGoing = snapshot.data!;
          return Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _updating ? null : () => _toggle(isGoing),
              icon: _updating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      isGoing ? Icons.event_available : Icons.event_outlined),
              label: Text(isGoing ? 'Going · tap to cancel' : 'I’m interested'),
            ),
          );
        },
      );
}
