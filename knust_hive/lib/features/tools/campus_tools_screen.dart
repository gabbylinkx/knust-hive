import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_theme.dart';
import 'cwa_calculator.dart';

class CampusToolsScreen extends StatelessWidget {
  const CampusToolsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 7,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Campus tools'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Academics'),
              Tab(text: 'Groups'),
              Tab(text: 'Marketplace'),
              Tab(text: 'Past questions'),
              Tab(text: 'Mentorship'),
              Tab(text: 'SOS'),
              Tab(text: 'Moderation'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _AcademicsTab(),
            _CommunitiesTab(),
            _MarketplaceTab(),
            _PastQuestionsTab(),
            _MentorshipTab(),
            _SosTab(),
            _ModerationTab(),
          ],
        ),
      ),
    );
  }
}

Future<void> _showMessage(BuildContext context, String message) async {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

Future<String?> _textDialog(
  BuildContext context, {
  required String title,
  required String label,
  int maxLength = 200,
  String? initialValue,
}) async {
  final controller = TextEditingController(text: initialValue);
  final value = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: maxLength,
        decoration: InputDecoration(labelText: label),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  controller.dispose();
  return value;
}

final _myCommunityIdsProvider = FutureProvider<Set<String>>((ref) async {
  final client = SupabaseService.client;
  final rows = await client
      .from('community_members')
      .select('community_id')
      .eq('user_id', client.auth.currentUser!.id);
  return rows.map((row) => row['community_id'] as String).toSet();
});

class _AcademicsTab extends ConsumerStatefulWidget {
  const _AcademicsTab();

  @override
  ConsumerState<_AcademicsTab> createState() => _AcademicsTabState();
}

class _AcademicsTabState extends ConsumerState<_AcademicsTab> {
  final client = SupabaseService.client;

  Future<void> _addClass() async {
    final course = await _textDialog(context,
        title: 'Add timetable class', label: 'Course name');
    if (course == null || course.isEmpty || !mounted) return;
    final room = await _textDialog(context,
        title: 'Class location', label: 'Room or venue (optional)');
    if (!mounted) return;
    final day = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Select day'),
        children: [
          for (var i = 1; i <= 7; i++)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, i % 7),
              child: Text(_weekday(i % 7)),
            ),
        ],
      ),
    );
    if (day == null || !mounted) return;
    final times = await _timeRangeDialog(context);
    if (times == null || !mounted) return;
    try {
      await client.from('timetable_entries').insert({
        'user_id': client.auth.currentUser!.id,
        'course_name': course,
        'day_of_week': day,
        'start_time': times.$1,
        'end_time': times.$2,
        'room': room?.isEmpty == true ? null : room,
      });
    } catch (error) {
      if (!mounted) return;
      await _showMessage(context, 'Could not save class: $error');
    }
  }

  Future<(String, String)?> _timeRangeDialog(BuildContext context) async {
    final start = TextEditingController(text: '09:00');
    final end = TextEditingController(text: '10:00');
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Class time (24-hour format)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: start,
              decoration: const InputDecoration(labelText: 'Start (HH:MM)'),
            ),
            TextField(
              controller: end,
              decoration: const InputDecoration(labelText: 'End (HH:MM)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (!_validTime(start.text) ||
                  !_validTime(end.text) ||
                  end.text.compareTo(start.text) <= 0) {
                _showMessage(context, 'Enter a valid time range on one day.');
                return;
              }
              Navigator.pop(context, (start.text, end.text));
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    start.dispose();
    end.dispose();
    return result;
  }

  bool _validTime(String value) =>
      RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(value);

  Future<void> _addCwaCourse() async {
    final code = await _textDialog(context,
        title: 'Add CWA course', label: 'Course code');
    if (code == null || code.isEmpty || !mounted) return;
    final semester = await _textDialog(
      context,
      title: 'Semester',
      label: 'e.g. 2026/27 Sem 1',
    );
    if (semester == null || semester.isEmpty || !mounted) return;
    final creditsRaw = await _textDialog(
      context,
      title: 'Credit hours',
      label: 'Number of credits',
    );
    final credits = double.tryParse(creditsRaw ?? '');
    if (credits == null || !credits.isFinite || credits <= 0 || !mounted) {
      if (mounted) await _showMessage(context, 'Enter positive credit hours.');
      return;
    }
    final scoreRaw = await _textDialog(
      context,
      title: 'Course mark',
      label: 'Percentage score (0–100)',
    );
    final score = double.tryParse(scoreRaw ?? '');
    if (score == null ||
        !score.isFinite ||
        score < 0 ||
        score > 100 ||
        !mounted) {
      if (mounted) await _showMessage(context, 'Enter a mark from 0 to 100.');
      return;
    }
    try {
      await client.from('cwa_records').insert({
        'user_id': client.auth.currentUser!.id,
        'course_code': code.toUpperCase(),
        'credit_hours': credits,
        'score': score,
        'semester': semester,
      });
    } catch (error) {
      if (!mounted) return;
      await _showMessage(context, 'Could not save course mark: $error');
    }
  }

  Future<void> _addLegacyCourseMark(Map<String, dynamic> row) async {
    final scoreRaw = await _textDialog(
      context,
      title: 'Enter actual course mark',
      label: 'Percentage score (0–100)',
    );
    if (scoreRaw == null || !mounted) return;
    final score = double.tryParse(scoreRaw);
    if (score == null || !score.isFinite || score < 0 || score > 100) {
      await _showMessage(context, 'Enter a mark from 0 to 100.');
      return;
    }
    try {
      await client
          .from('cwa_records')
          .update({'score': score}).eq('id', row['id']);
    } catch (error) {
      if (!mounted) return;
      await _showMessage(context, 'Could not update course mark: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final userId = client.auth.currentUser!.id;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SectionHeading(
          title: 'Timetable',
          action: IconButton(
            tooltip: 'Add class',
            onPressed: _addClass,
            icon: const Icon(Icons.add),
          ),
        ),
        _SupabaseList(
          stream: client
              .from('timetable_entries')
              .stream(primaryKey: ['id'])
              .eq('user_id', userId)
              .order('day_of_week')
              .limit(100),
          emptyText: 'Add your classes to build a weekly timetable.',
          builder: (rows) => Column(
            children: [
              for (final row in rows)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.schedule),
                    title: Text(row['course_name'] as String? ?? 'Class'),
                    subtitle: Text(
                      '${_weekday(row['day_of_week'] as int? ?? 0)} · '
                      '${_shortTime(row['start_time'])}–${_shortTime(row['end_time'])}'
                      '${row['room'] == null ? '' : ' · ${row['room']}'}',
                    ),
                    trailing: IconButton(
                      tooltip: 'Delete class',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        try {
                          await client
                              .from('timetable_entries')
                              .delete()
                              .eq('id', row['id']);
                        } catch (error) {
                          if (!context.mounted) return;
                          await _showMessage(
                              context, 'Could not delete class: $error');
                        }
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _SectionHeading(
          title: 'CWA tracker',
          action: IconButton(
            tooltip: 'Add course mark',
            onPressed: _addCwaCourse,
            icon: const Icon(Icons.add),
          ),
        ),
        _SupabaseList(
          stream: client
              .from('cwa_records')
              .stream(primaryKey: ['id'])
              .eq('user_id', userId)
              .order('semester')
              .limit(200),
          emptyText: 'Add percentage marks to calculate your cumulative CWA.',
          builder: (rows) {
            final scoredRows = rows.where((row) => row['score'] != null);
            final cwa = calculateCwa(scoredRows.map((row) => (
                  score: (row['score'] as num).toDouble(),
                  creditHours: (row['credit_hours'] as num).toDouble(),
                )));
            final legacyCount = rows.length - scoredRows.length;
            return Column(
              children: [
                Card(
                  color: AppColors.forest,
                  child: ListTile(
                    title: const Text('Cumulative Weighted Average',
                        style: TextStyle(color: Colors.white)),
                    subtitle: Text(
                      cwa == null
                          ? 'Add percentage marks to begin'
                          : 'Based on ${scoredRows.length} marked courses',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    trailing: Text(
                      cwa == null ? '—' : '${cwa.toStringAsFixed(2)}%',
                      style: const TextStyle(
                        color: AppColors.gold,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                if (legacyCount > 0)
                  const Card(
                    child: ListTile(
                      leading: Icon(Icons.info_outline),
                      title: Text('Older letter-grade records'),
                      subtitle: Text(
                        'These are not included in CWA because the original percentage marks were not saved. Add each actual mark to include it.',
                      ),
                    ),
                  ),
                for (final row in rows)
                  Card(
                    child: ListTile(
                      title: Text(row['score'] == null
                          ? '${row['course_code']} · Legacy grade ${row['grade'] ?? ''}'
                          : '${row['course_code']} · ${(row['score'] as num).toStringAsFixed(2)}%'),
                      subtitle: Text(
                          '${row['semester']} · ${row['credit_hours']} credits'),
                      trailing: row['score'] == null
                          ? IconButton(
                              tooltip: 'Enter actual percentage mark',
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () => _addLegacyCourseMark(row),
                            )
                          : IconButton(
                              tooltip: 'Delete course result',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () async {
                                try {
                                  await client
                                      .from('cwa_records')
                                      .delete()
                                      .eq('id', row['id']);
                                } catch (error) {
                                  if (!context.mounted) return;
                                  await _showMessage(context,
                                      'Could not delete course result: $error');
                                }
                              },
                            ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

String _weekday(int day) => switch (day) {
      0 => 'Sunday',
      1 => 'Monday',
      2 => 'Tuesday',
      3 => 'Wednesday',
      4 => 'Thursday',
      5 => 'Friday',
      _ => 'Saturday',
    };

String _shortTime(dynamic value) {
  final text = value?.toString();
  return text == null || text.length < 5 ? '—' : text.substring(0, 5);
}

class _CommunitiesTab extends ConsumerWidget {
  const _CommunitiesTab();

  Future<void> _create(BuildContext context) async {
    final name =
        await _textDialog(context, title: 'Create a community', label: 'Name');
    if (name == null || name.isEmpty || !context.mounted) return;
    final description = await _textDialog(
      context,
      title: 'Community description',
      label: 'What is this group for?',
      maxLength: 500,
    );
    if (!context.mounted) return;
    try {
      final client = SupabaseService.client;
      final community = await client
          .from('communities')
          .insert({'name': name, 'description': description})
          .select('id')
          .single();
      await client.from('community_members').insert({
        'community_id': community['id'],
        'user_id': client.auth.currentUser!.id,
      });
    } catch (error) {
      if (!context.mounted) return;
      await _showMessage(context, 'Could not create community: $error');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = SupabaseService.client;
    final userId = client.auth.currentUser!.id;
    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => _create(context),
            icon: const Icon(Icons.add),
            label: const Text('Create group'),
          ),
        ),
        Expanded(
          child: _SupabaseList(
            stream: client
                .from('communities')
                .stream(primaryKey: ['id']).order('name'),
            emptyText: 'No communities yet.',
            builder: (communities) => ref.watch(_myCommunityIdsProvider).when(
                  error: (error, _) => Center(
                    child: Text('Could not load your groups: $error'),
                  ),
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  data: (joined) {
                    return ListView(
                      padding: const EdgeInsets.all(12),
                      children: [
                        for (final community in communities)
                          Card(
                            child: ListTile(
                              leading: const Icon(Icons.groups_outlined),
                              title: Text(
                                  community['name'] as String? ?? 'Community'),
                              subtitle: Text(
                                community['description'] as String? ??
                                    'Student community',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: FilledButton.tonal(
                                onPressed: () async {
                                  try {
                                    final query = client
                                        .from('community_members')
                                        .delete()
                                        .eq('community_id', community['id'])
                                        .eq('user_id', userId);
                                    if (joined.contains(community['id'])) {
                                      await query;
                                    } else {
                                      await client
                                          .from('community_members')
                                          .insert({
                                        'community_id': community['id'],
                                        'user_id': userId,
                                      });
                                    }
                                    ref.invalidate(_myCommunityIdsProvider);
                                  } catch (error) {
                                    if (!context.mounted) return;
                                    await _showMessage(context,
                                        'Could not update membership: $error');
                                  }
                                },
                                child: Text(
                                  joined.contains(community['id'])
                                      ? 'Leave'
                                      : 'Join',
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
          ),
        ),
      ],
    );
  }
}

class _MarketplaceTab extends ConsumerWidget {
  const _MarketplaceTab();

  Future<void> _create(BuildContext context) async {
    final title =
        await _textDialog(context, title: 'New listing', label: 'Item name');
    if (title == null || title.isEmpty || !context.mounted) return;
    final description = await _textDialog(
      context,
      title: 'Item details',
      label: 'Description (optional)',
      maxLength: 500,
    );
    if (!context.mounted) return;
    final priceRaw = await _textDialog(
      context,
      title: 'Asking price',
      label: 'GHS amount (leave blank for free)',
    );
    if (!context.mounted) return;
    final price =
        priceRaw == null || priceRaw.isEmpty ? null : double.tryParse(priceRaw);
    if (priceRaw != null && priceRaw.isNotEmpty && price == null) {
      await _showMessage(context, 'Enter a valid price.');
      return;
    }
    try {
      await SupabaseService.client.from('marketplace_listings').insert({
        'seller_id': SupabaseService.client.auth.currentUser!.id,
        'title': title,
        'description': description,
        'price': price,
      });
    } catch (error) {
      if (!context.mounted) return;
      await _showMessage(context, 'Could not create listing: $error');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = SupabaseService.client;
    final userId = client.auth.currentUser!.id;
    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => _create(context),
            icon: const Icon(Icons.add),
            label: const Text('Sell an item'),
          ),
        ),
        Expanded(
          child: _SupabaseList(
            stream: client
                .from('marketplace_listings')
                .stream(primaryKey: ['id'])
                .order('created_at', ascending: false)
                .limit(100),
            emptyText: 'The campus marketplace is empty. Be the first to list.',
            builder: (rows) => ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: rows.length,
              itemBuilder: (context, index) {
                final row = rows[index];
                final mine = row['seller_id'] == userId;
                final price = double.tryParse('${row['price']}');
                return Card(
                  child: ListTile(
                    leading: Icon(
                      row['status'] == 'sold'
                          ? Icons.check_circle_outline
                          : Icons.storefront_outlined,
                    ),
                    title: Text(row['title'] as String? ?? 'Listing'),
                    subtitle: Text(
                      '${price == null ? 'Free' : 'GHS ${price.toStringAsFixed(2)}'}'
                      '${row['description'] == null ? '' : ' · ${row['description']}'}'
                      '${row['status'] == 'sold' ? ' · Sold' : ''}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: mine && row['status'] != 'sold'
                        ? IconButton(
                            tooltip: 'Mark as sold',
                            icon: const Icon(Icons.done),
                            onPressed: () async {
                              try {
                                await client
                                    .from('marketplace_listings')
                                    .update({'status': 'sold'}).eq(
                                        'id', row['id']);
                              } catch (error) {
                                if (!context.mounted) return;
                                await _showMessage(context,
                                    'Could not update listing: $error');
                              }
                            },
                          )
                        : null,
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _PastQuestionsTab extends ConsumerWidget {
  const _PastQuestionsTab();

  Future<void> _uploadLink(BuildContext context) async {
    final code = await _textDialog(
      context,
      title: 'Share past questions',
      label: 'Course code',
    );
    if (code == null || code.isEmpty || !context.mounted) return;
    final yearRaw = await _textDialog(
      context,
      title: 'Exam year',
      label: 'Year (optional)',
    );
    if (!context.mounted) return;
    final url =
        await _textDialog(context, title: 'Document link', label: 'HTTPS URL');
    if (url == null || url.isEmpty || !context.mounted) return;
    final uri = Uri.tryParse(url);
    final year =
        yearRaw == null || yearRaw.isEmpty ? null : int.tryParse(yearRaw);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        (yearRaw != null && yearRaw.isNotEmpty && year == null)) {
      await _showMessage(
          context, 'Enter a valid HTTPS link and optional year.');
      return;
    }
    try {
      await SupabaseService.client.from('past_questions').insert({
        'course_code': code.toUpperCase(),
        'year': year,
        'file_url': uri.toString(),
        'uploaded_by': SupabaseService.client.auth.currentUser!.id,
      });
    } catch (error) {
      if (!context.mounted) return;
      await _showMessage(context, 'Could not share past questions: $error');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = SupabaseService.client;
    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => _uploadLink(context),
            icon: const Icon(Icons.link),
            label: const Text('Share document link'),
          ),
        ),
        Expanded(
          child: _SupabaseList(
            stream: client
                .from('past_questions')
                .stream(primaryKey: ['id'])
                .order('course_code')
                .limit(200),
            emptyText: 'No past-question documents have been shared yet.',
            builder: (rows) => ListView(
              padding: const EdgeInsets.all(12),
              children: [
                for (final row in rows)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.description_outlined),
                      title: Text(
                          '${row['course_code']} · ${row['year'] ?? 'Year n/a'}'),
                      subtitle: const Text('Open shared document'),
                      onTap: () async {
                        final uri =
                            Uri.tryParse(row['file_url'] as String? ?? '');
                        if (uri == null || uri.scheme != 'https') {
                          if (!context.mounted) return;
                          await _showMessage(
                              context, 'This document link is invalid.');
                          return;
                        }
                        try {
                          if (!await launchUrl(uri,
                              mode: LaunchMode.externalApplication)) {
                            if (!context.mounted) return;
                            await _showMessage(
                                context, 'Could not open this document.');
                          }
                        } catch (error) {
                          if (!context.mounted) return;
                          await _showMessage(
                              context, 'Could not open document: $error');
                        }
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _MentorshipTab extends ConsumerStatefulWidget {
  const _MentorshipTab();

  @override
  ConsumerState<_MentorshipTab> createState() => _MentorshipTabState();
}

class _MentorshipTabState extends ConsumerState<_MentorshipTab> {
  late Future<List<Map<String, dynamic>>> profiles;
  late Future<List<Map<String, dynamic>>> requests;

  @override
  void initState() {
    super.initState();
    profiles = _loadProfiles();
    requests = _loadRequests();
  }

  Future<List<Map<String, dynamic>>> _loadProfiles() {
    final client = SupabaseService.client;
    return client
        .from('profiles')
        .select('id, display_name, faculty, department, year_group')
        .neq('id', client.auth.currentUser!.id)
        .limit(100);
  }

  Future<List<Map<String, dynamic>>> _loadRequests() {
    final client = SupabaseService.client;
    final userId = client.auth.currentUser!.id;
    return client
        .from('mentorships')
        .select('mentor_id, mentee_id, status, created_at')
        .or('mentor_id.eq.$userId,mentee_id.eq.$userId')
        .order('created_at', ascending: false);
  }

  Future<void> _respond(Map<String, dynamic> request, String status) async {
    final client = SupabaseService.client;
    try {
      await client
          .from('mentorships')
          .update({'status': status})
          .eq('mentor_id', request['mentor_id'])
          .eq('mentee_id', request['mentee_id']);
      if (!mounted) return;
      setState(() => requests = _loadRequests());
      await _showMessage(
        context,
        status == 'active'
            ? 'Mentorship request accepted.'
            : 'Request declined.',
      );
    } catch (error) {
      if (!mounted) return;
      await _showMessage(context, 'Could not update request: $error');
    }
  }

  Map<String, dynamic>? _requestFor(
    List<Map<String, dynamic>> rows,
    String otherUserId,
    String userId,
  ) {
    for (final row in rows) {
      if ((row['mentor_id'] == userId && row['mentee_id'] == otherUserId) ||
          (row['mentee_id'] == userId && row['mentor_id'] == otherUserId)) {
        return row;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final client = SupabaseService.client;
    final userId = client.auth.currentUser!.id;
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: requests,
      builder: (context, requestSnapshot) {
        if (requestSnapshot.hasError) {
          return Center(
              child: Text(
                  'Could not load mentorship requests: ${requestSnapshot.error}'));
        }
        if (!requestSnapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final requestRows = requestSnapshot.data!;
        return FutureBuilder<List<Map<String, dynamic>>>(
          future: profiles,
          builder: (context, profileSnapshot) {
            if (profileSnapshot.hasError) {
              return Center(
                  child: Text(
                      'Could not load students: ${profileSnapshot.error}'));
            }
            if (!profileSnapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final students = profileSnapshot.data!;
            final byId = {
              for (final profile in students) profile['id']: profile,
            };
            return ListView(
              padding: const EdgeInsets.all(12),
              children: [
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.info_outline),
                    title: Text('Find a mentor'),
                    subtitle: Text(
                      'Send a request to a student. They can accept or decline it here.',
                    ),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: Text('Requests',
                          style: Theme.of(context).textTheme.titleMedium),
                    ),
                    IconButton(
                      tooltip: 'Refresh requests',
                      onPressed: () =>
                          setState(() => requests = _loadRequests()),
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
                if (requestRows.isEmpty)
                  const ListTile(title: Text('No mentorship requests yet.')),
                for (final request in requestRows)
                  Builder(builder: (context) {
                    final incoming = request['mentor_id'] == userId;
                    final otherId =
                        incoming ? request['mentee_id'] : request['mentor_id'];
                    final name =
                        byId[otherId]?['display_name'] as String? ?? 'Student';
                    final status = request['status'] as String? ?? 'pending';
                    return Card(
                      child: ListTile(
                        title: Text(name),
                        subtitle:
                            Text('${incoming ? 'Incoming' : 'Sent'} · $status'),
                        trailing: incoming && status == 'pending'
                            ? Wrap(
                                children: [
                                  IconButton(
                                    tooltip: 'Decline',
                                    onPressed: () => _respond(request, 'ended'),
                                    icon: const Icon(Icons.close),
                                  ),
                                  IconButton(
                                    tooltip: 'Accept',
                                    onPressed: () =>
                                        _respond(request, 'active'),
                                    icon: const Icon(Icons.check),
                                  ),
                                ],
                              )
                            : null,
                      ),
                    );
                  }),
                const SizedBox(height: 12),
                Text('Students',
                    style: Theme.of(context).textTheme.titleMedium),
                if (students.isEmpty)
                  const ListTile(
                      title: Text('No other profiles are available.')),
                for (final profile in students)
                  Builder(builder: (context) {
                    final existing = _requestFor(
                        requestRows, profile['id'] as String, userId);
                    final status = existing?['status'] as String?;
                    return Card(
                      child: ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.person)),
                        title: Text(
                            profile['display_name'] as String? ?? 'Student'),
                        subtitle: Text(
                          [
                            profile['department'],
                            profile['faculty'],
                            if (profile['year_group'] != null)
                              'Year ${profile['year_group']}',
                          ]
                              .whereType<String>()
                              .where((value) => value.isNotEmpty)
                              .join(' · '),
                        ),
                        trailing: existing == null
                            ? IconButton(
                                tooltip: 'Request mentorship',
                                icon: const Icon(Icons.handshake_outlined),
                                onPressed: () async {
                                  try {
                                    await client.from('mentorships').insert({
                                      'mentor_id': profile['id'],
                                      'mentee_id': userId,
                                    });
                                    if (mounted) {
                                      setState(
                                          () => requests = _loadRequests());
                                    }
                                    if (context.mounted) {
                                      await _showMessage(
                                          context, 'Mentorship request sent.');
                                    }
                                  } catch (error) {
                                    if (!context.mounted) return;
                                    await _showMessage(context,
                                        'Could not send request: $error');
                                  }
                                },
                              )
                            : Text(status ?? 'Requested'),
                      ),
                    );
                  }),
              ],
            );
          },
        );
      },
    );
  }
}

class _SosTab extends StatelessWidget {
  const _SosTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Icon(Icons.sos, color: AppColors.clay, size: 56),
        Text(
          'Emergency help',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        const Text(
          'If you are in immediate danger, contact Ghana’s emergency number. '
          'This button opens your phone dialer and does not send your location.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: AppColors.clay),
          onPressed: () async {
            final uri = Uri(scheme: 'tel', path: '112');
            try {
              if (!await launchUrl(uri)) {
                if (!context.mounted) return;
                await _showMessage(
                    context, 'Your device could not open the dialer.');
              }
            } catch (error) {
              if (!context.mounted) return;
              await _showMessage(context, 'Could not open dialer: $error');
            }
          },
          icon: const Icon(Icons.call),
          label: const Text('Call emergency services · 112'),
        ),
        const SizedBox(height: 16),
        const Card(
          child: ListTile(
            leading: Icon(Icons.privacy_tip_outlined),
            title: Text('Your privacy'),
            subtitle: Text(
              'KNUST Hive does not automatically call, message contacts, or share GPS. '
              'Contact your hall or campus security using the number officially provided to you.',
            ),
          ),
        ),
      ],
    );
  }
}

class _ModerationTab extends ConsumerWidget {
  const _ModerationTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = SupabaseService.client;
    final userId = client.auth.currentUser!.id;
    return FutureBuilder<Map<String, dynamic>?>(
      future: client
          .from('profiles')
          .select('is_admin')
          .eq('id', userId)
          .maybeSingle(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
              child:
                  Text('Could not check moderation access: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.data?['is_admin'] != true) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Moderation tools are restricted to designated moderators. '
                'Contact a project administrator if you need access.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return _SupabaseList(
          stream: client
              .from('moderation_reports')
              .stream(primaryKey: ['id'])
              .eq('status', 'open')
              .order('created_at', ascending: false)
              .limit(200),
          emptyText: 'No open moderation reports.',
          builder: (rows) => ListView(
            padding: const EdgeInsets.all(12),
            children: [
              for (final row in rows)
                Card(
                  child: ListTile(
                    title:
                        Text('${row['content_type']} · ${row['content_id']}'),
                    subtitle: Text(
                      '${row['reason']}\nStatus: ${row['status']}',
                    ),
                    isThreeLine: true,
                    trailing: row['status'] == 'open'
                        ? IconButton(
                            tooltip: 'Resolve report',
                            icon: const Icon(Icons.check_circle_outline),
                            onPressed: () async {
                              try {
                                await client.from('moderation_reports').update({
                                  'status': 'resolved',
                                  'resolved_by': userId,
                                }).eq('id', row['id']);
                              } catch (error) {
                                if (!context.mounted) return;
                                await _showMessage(context,
                                    'Could not resolve report: $error');
                              }
                            },
                          )
                        : null,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, required this.action});

  final String title;
  final Widget action;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          action,
        ],
      );
}

class _SupabaseList extends StatelessWidget {
  const _SupabaseList({
    required this.stream,
    required this.emptyText,
    required this.builder,
  });

  final Stream<List<Map<String, dynamic>>> stream;
  final String emptyText;
  final Widget Function(List<Map<String, dynamic>>) builder;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Could not load data: ${snapshot.error}'),
          );
        }
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.data!.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text(emptyText, textAlign: TextAlign.center),
          );
        }
        return builder(snapshot.data!);
      },
    );
  }
}
