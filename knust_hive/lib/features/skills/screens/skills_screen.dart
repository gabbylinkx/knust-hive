import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_theme.dart';

class SkillsScreen extends ConsumerStatefulWidget {
  const SkillsScreen({super.key});

  @override
  ConsumerState<SkillsScreen> createState() => _SkillsScreenState();
}

class _SkillsScreenState extends ConsumerState<SkillsScreen> {
  late Future<(List<Map<String, dynamic>>, Map<String, String>)> _data;

  @override
  void initState() {
    super.initState();
    _data = _load();
  }

  Future<(List<Map<String, dynamic>>, Map<String, String>)> _load() async {
    final client = SupabaseService.client;
    final userId = client.auth.currentUser!.id;
    final results = await Future.wait([
      client.from('skill_paths').select().order('title').limit(100),
      client
          .from('user_skill_progress')
          .select('skill_id, status')
          .eq('user_id', userId),
    ]);
    final skills = (results[0] as List).cast<Map<String, dynamic>>();
    final progressRows = (results[1] as List).cast<Map<String, dynamic>>();
    return (
      skills,
      {
        for (final row in progressRows)
          row['skill_id'] as String: row['status'] as String
      }
    );
  }

  Future<void> _setComplete(String skillId, String? currentStatus) async {
    final client = SupabaseService.client;
    final userId = client.auth.currentUser!.id;
    final nextStatus = currentStatus == 'completed' ? 'started' : 'completed';
    try {
      await client.from('user_skill_progress').upsert(
        {
          'user_id': userId,
          'skill_id': skillId,
          'status': nextStatus,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'user_id,skill_id',
      );
      if (mounted) setState(() => _data = _load());
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save learning progress: $error')),
        );
      }
    }
  }

  Future<void> _openResource(String? value) async {
    final uri = Uri.tryParse(value ?? '');
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      _showError('This resource does not have a valid HTTPS link.');
      return;
    }
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        _showError('Could not open this learning resource.');
      }
    } catch (error) {
      _showError('Could not open learning resource: $error');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Skills & growth'),
        actions: [
          IconButton(
            tooltip: 'Refresh resources',
            onPressed: () => setState(() => _data = _load()),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<(List<Map<String, dynamic>>, Map<String, String>)>(
        future: _data,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                    'Could not load learning resources: ${snapshot.error}'),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final (skills, progress) = snapshot.data!;
          if (skills.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No learning resources have been added yet. Ask a project moderator to add resources.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final completedCount =
              progress.values.where((status) => status == 'completed').length;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                color: AppColors.forest,
                child: ListTile(
                  leading:
                      const Icon(Icons.school_outlined, color: AppColors.gold),
                  title: const Text('Your progress',
                      style: TextStyle(color: Colors.white)),
                  subtitle: Text(
                    '$completedCount of ${skills.length} resources completed',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  trailing: Text(
                    '${skills.isEmpty ? 0 : (completedCount * 100 ~/ skills.length)}%',
                    style: const TextStyle(
                      color: AppColors.gold,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
              ),
              for (final skill in skills)
                _SkillTile(
                  skill: skill,
                  status: progress[skill['id'] as String],
                  onToggle: () => _setComplete(
                    skill['id'] as String,
                    progress[skill['id'] as String],
                  ),
                  onOpen: () => _openResource(skill['resource_url'] as String?),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _SkillTile extends StatelessWidget {
  const _SkillTile({
    required this.skill,
    required this.status,
    required this.onToggle,
    required this.onOpen,
  });

  final Map<String, dynamic> skill;
  final String? status;
  final VoidCallback onToggle;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final completed = status == 'completed';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: IconButton(
          tooltip: completed ? 'Mark in progress' : 'Mark complete',
          icon: Icon(
            completed ? Icons.check_circle : Icons.circle_outlined,
            color: completed ? AppColors.forest : const Color(0xFFCBD1BE),
          ),
          onPressed: onToggle,
        ),
        title: Text(
          skill['title'] as String? ?? 'Learning resource',
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          [
            if (skill['tag'] != null) '${skill['tag']} · ',
            skill['description'] as String? ?? '',
            if (completed) ' · Completed',
          ].join(),
          style: const TextStyle(fontSize: 12),
        ),
        trailing: IconButton(
          tooltip: 'Open learning resource',
          icon:
              const Icon(Icons.open_in_new, size: 16, color: AppColors.forest),
          onPressed: onOpen,
        ),
      ),
    );
  }
}
