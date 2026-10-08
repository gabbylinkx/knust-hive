import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../shuttle/providers/shuttle_providers.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  late final Future<Box<String>> taskBox =
      Hive.openBox<String>('dashboard_tasks');
  final taskController = TextEditingController();
  bool addingTask = false;

  @override
  void dispose() {
    taskController.dispose();
    super.dispose();
  }

  Future<void> _addTask(Box<String> box) async {
    taskController.clear();
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add a task'),
        content: TextField(
          controller: taskController,
          autofocus: true,
          maxLength: 120,
          textCapitalization: TextCapitalization.sentences,
          decoration:
              const InputDecoration(hintText: 'What do you need to do?'),
          onSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, taskController.text.trim()),
            child: const Text('Add task'),
          ),
        ],
      ),
    );
    if (title == null || title.isEmpty || !mounted) return;
    setState(() => addingTask = true);
    try {
      final id = DateTime.now().microsecondsSinceEpoch.toString();
      await box.put(id, jsonEncode({'title': title, 'done': false}));
    } catch (error) {
      if (mounted) _showError('Could not save task: $error');
    } finally {
      if (mounted) setState(() => addingTask = false);
    }
  }

  Future<void> _toggleTask(Box<String> box, String id, String value) async {
    try {
      final task = jsonDecode(value) as Map<String, dynamic>;
      await box.put(
          id, jsonEncode({'title': task['title'], 'done': !task['done']}));
    } catch (error) {
      if (mounted) _showError('Could not update task: $error');
    }
  }

  Future<void> _deleteTask(Box<String> box, String id) async {
    try {
      await box.delete(id);
    } catch (error) {
      if (mounted) _showError('Could not remove task: $error');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final colors = Theme.of(context).colorScheme;
    final greeting = now.hour < 12
        ? 'Good morning'
        : now.hour < 17
            ? 'Good afternoon'
            : 'Good evening';
    final userId = SupabaseService.client.auth.currentUser!.id;
    final reportsAsync = ref.watch(shuttleReportsProvider);
    final ridesAsync = ref.watch(ridePostsProvider);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'KNUST Hive',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            Text(
              'Your campus, connected.',
              style: TextStyle(
                color: colors.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Profile',
            onPressed: () => context.push('/profile'),
            icon: CircleAvatar(
              radius: 17,
              backgroundColor: colors.primary,
              child: Icon(Icons.person, size: 18, color: colors.onPrimary),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          Text(greeting, style: Theme.of(context).textTheme.headlineSmall),
          Text(
            DateFormat('EEEE, MMMM d').format(now),
            style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13),
          ),
          const SizedBox(height: 18),
          const _CampusWelcomeCard(),
          const SizedBox(height: 20),
          Text('Campus at a glance',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: reportsAsync.when(
                data: (reports) => _StatCard(
                    label: 'Shuttle sightings (30m)',
                    value: reports.where((report) => report.isFresh).length,
                    icon: Icons.directions_bus),
                loading: () =>
                    const _StatLoadingCard(label: 'Shuttle sightings'),
                error: (error, _) =>
                    _StatErrorCard(label: 'Shuttle sightings', error: '$error'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ridesAsync.when(
                data: (rides) => _StatCard(
                    label: 'Open ride posts',
                    value: rides.length,
                    icon: Icons.people),
                loading: () => const _StatLoadingCard(label: 'Open ride posts'),
                error: (error, _) =>
                    _StatErrorCard(label: 'Open ride posts', error: '$error'),
              ),
            ),
          ]),
          const SizedBox(height: 22),
          Text("Today's schedule",
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _TodaySchedule(userId: userId, day: now.weekday % 7),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: Text('To-do',
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              FutureBuilder<Box<String>>(
                future: taskBox,
                builder: (context, snapshot) => IconButton(
                  tooltip: 'Add task',
                  onPressed: snapshot.hasData && !addingTask
                      ? () => _addTask(snapshot.data!)
                      : null,
                  icon: addingTask
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          FutureBuilder<Box<String>>(
            future: taskBox,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return _EmptyCard(
                    icon: Icons.error_outline,
                    text: 'Could not load tasks: ${snapshot.error}');
              }
              if (!snapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final box = snapshot.data!;
              return ValueListenableBuilder(
                valueListenable: box.listenable(),
                builder: (context, Box<String> taskBox, _) {
                  final tasks = taskBox.keys
                      .whereType<String>()
                      .map((id) => (id, taskBox.get(id)!))
                      .toList()
                    ..sort((a, b) => a.$1.compareTo(b.$1));
                  if (tasks.isEmpty) {
                    return const _EmptyCard(
                      icon: Icons.checklist,
                      text:
                          'Your task list is empty. Add a task to get started.',
                    );
                  }
                  return Column(
                    children: [
                      for (final (id, value) in tasks)
                        _TaskTile(
                          id: id,
                          value: value,
                          onToggle: () => _toggleTask(taskBox, id, value),
                          onDelete: () => _deleteTask(taskBox, id),
                        ),
                    ],
                  );
                },
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Tasks are saved on this device and are not synced between devices.',
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CampusWelcomeCard extends StatelessWidget {
  const _CampusWelcomeCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.forest, AppColors.forestLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: Color(0x33FFFFFF),
            child: Icon(Icons.hive_rounded, color: AppColors.gold),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Campus life, in sync.',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                SizedBox(height: 5),
                Text(
                  'Keep classes, shuttle activity and student life close at hand.',
                  style: TextStyle(
                    color: AppColors.goldSoft,
                    height: 1.4,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TodaySchedule extends StatelessWidget {
  const _TodaySchedule({required this.userId, required this.day});

  final String userId;
  final int day;

  @override
  Widget build(BuildContext context) {
    final stream = SupabaseService.client
        .from('timetable_entries')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .eq('day_of_week', day)
        .order('start_time')
        .limit(50);
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _EmptyCard(
              icon: Icons.error_outline,
              text: 'Could not load today’s timetable: ${snapshot.error}');
        }
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final rows = snapshot.data!;
        if (rows.isEmpty) {
          return const _EmptyCard(
            icon: Icons.calendar_today_outlined,
            text:
                'No classes scheduled for today. Your timetable is under More.',
          );
        }
        return Column(
          children: [
            for (final row in rows)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.schedule, color: AppColors.forest),
                  title: Text(row['course_name'] as String? ?? 'Class'),
                  subtitle: Text(
                    '${_formatTime(row['start_time'])}–${_formatTime(row['end_time'])}'
                    '${row['room'] == null ? '' : ' · ${row['room']}'}',
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  String _formatTime(dynamic value) {
    final raw = value?.toString() ?? '';
    return raw.length >= 5 ? raw.substring(0, 5) : '—';
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({
    required this.id,
    required this.value,
    required this.onToggle,
    required this.onDelete,
  });

  final String id;
  final String value;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final task = jsonDecode(value) as Map<String, dynamic>;
    final done = task['done'] == true;
    return Card(
      child: ListTile(
        leading: Checkbox(value: done, onChanged: (_) => onToggle()),
        title: Text(
          task['title'] as String? ?? 'Task',
          style: TextStyle(
            decoration: done ? TextDecoration.lineThrough : null,
            color: done ? Theme.of(context).disabledColor : null,
          ),
        ),
        trailing: IconButton(
          tooltip: 'Delete task',
          onPressed: onDelete,
          icon: const Icon(Icons.delete_outline),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard(
      {required this.label, required this.value, required this.icon});

  final String label;
  final int value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.gold.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: colors.primary, size: 20),
            ),
            const SizedBox(height: 12),
            Text('$value', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(color: colors.onSurfaceVariant, fontSize: 11.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatErrorCard extends StatelessWidget {
  const _StatErrorCard({required this.label, required this.error});

  final String label;
  final String error;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline, size: 18, color: AppColors.clay),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(fontSize: 11)),
            Text(
              'Unavailable: $error',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, color: AppColors.clay),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatLoadingCard extends StatelessWidget {
  const _StatLoadingCard({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(height: 12),
            Text(label, style: const TextStyle(fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        dense: true,
        leading: Icon(icon, size: 18, color: AppColors.forest),
        title: Text(text, style: const TextStyle(fontSize: 13.5)),
      ),
    );
  }
}
