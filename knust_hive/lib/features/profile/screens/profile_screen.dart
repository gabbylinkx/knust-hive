import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/models.dart';
import '../../auth/providers/auth_provider.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  late Future<UserProfile?> profile;
  bool signingOut = false;

  @override
  void initState() {
    super.initState();
    profile = _loadProfile();
  }

  Future<UserProfile?> _loadProfile() async {
    final client = SupabaseService.client;
    final user = client.auth.currentUser;
    if (user == null) return null;
    final row = await client
        .from('profiles')
        .select(
            'id, display_name, faculty, department, year_group, interests, avatar_url')
        .eq('id', user.id)
        .maybeSingle();
    return row == null ? null : UserProfile.fromMap(row);
  }

  Future<void> _editProfile(UserProfile current) async {
    final formKey = GlobalKey<FormState>();
    final name = TextEditingController(text: current.displayName);
    final faculty = TextEditingController(text: current.faculty ?? '');
    final department = TextEditingController(text: current.department ?? '');
    final year =
        TextEditingController(text: current.yearGroup?.toString() ?? '');
    final interests = TextEditingController(text: current.interests.join(', '));
    var saving = false;
    String? error;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit profile'),
          content: SizedBox(
            width: 420,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: name,
                      textCapitalization: TextCapitalization.words,
                      decoration:
                          const InputDecoration(labelText: 'Display name'),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                              ? 'Enter your name'
                              : null,
                    ),
                    TextField(
                      controller: faculty,
                      decoration: const InputDecoration(labelText: 'Faculty'),
                    ),
                    TextField(
                      controller: department,
                      decoration:
                          const InputDecoration(labelText: 'Department'),
                    ),
                    TextField(
                      controller: year,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: 'Year group'),
                    ),
                    TextField(
                      controller: interests,
                      decoration: const InputDecoration(
                          labelText: 'Interests (comma separated)'),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 8),
                      Text(error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                    ],
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      final parsedYear = year.text.trim().isEmpty
                          ? null
                          : int.tryParse(year.text.trim());
                      if (year.text.trim().isNotEmpty &&
                          (parsedYear == null ||
                              parsedYear < 1 ||
                              parsedYear > 10)) {
                        setDialogState(
                            () => error = 'Enter a valid year group.');
                        return;
                      }
                      setDialogState(() {
                        saving = true;
                        error = null;
                      });
                      final interestsList = interests.text
                          .split(',')
                          .map((value) => value.trim())
                          .where((value) => value.isNotEmpty)
                          .toSet()
                          .toList();
                      final updates = {
                        'display_name': name.text.trim(),
                        'faculty': faculty.text.trim().isEmpty
                            ? null
                            : faculty.text.trim(),
                        'department': department.text.trim().isEmpty
                            ? null
                            : department.text.trim(),
                        'year_group': parsedYear,
                        'interests': interestsList,
                      };
                      try {
                        await SupabaseService.client
                            .from('profiles')
                            .update(updates)
                            .eq('id', current.id);
                        await SupabaseService.client.auth.updateUser(
                          UserAttributes(
                            data: {
                              'display_name': name.text.trim(),
                              'full_name': name.text.trim(),
                            },
                          ),
                        );
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext);
                        }
                        if (mounted) {
                          setState(() => profile = _loadProfile());
                        }
                      } catch (exception) {
                        setDialogState(() {
                          error = 'Could not save your profile: $exception';
                          saving = false;
                        });
                      }
                    },
              child: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    faculty.dispose();
    department.dispose();
    year.dispose();
    interests.dispose();
  }

  Future<void> _signOut() async {
    setState(() => signingOut = true);
    try {
      await ref.read(authActionsProvider).signOut();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not sign out: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => signingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = SupabaseService.client.auth.currentUser;
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: FutureBuilder<UserProfile?>(
        future: profile,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Could not load your profile: ${snapshot.error}'),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final student = snapshot.data;
          if (student == null) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Your student profile is not complete yet. Sign out and finish student verification to continue.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              CircleAvatar(
                radius: 38,
                backgroundColor: AppColors.paperDim,
                backgroundImage: student.avatarUrl == null
                    ? null
                    : NetworkImage(student.avatarUrl!),
                child: student.avatarUrl == null
                    ? const Icon(Icons.person,
                        size: 38, color: AppColors.forest)
                    : null,
              ),
              const SizedBox(height: 12),
              Text(
                student.displayName,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                user?.email ?? 'Not signed in',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF5B6355)),
              ),
              const SizedBox(height: 10),
              Center(
                child: OutlinedButton.icon(
                  onPressed: () => _editProfile(student),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit profile'),
                ),
              ),
              const Divider(height: 32),
              _ProfileField(
                  label: 'Faculty', value: student.faculty ?? 'Not provided'),
              _ProfileField(
                  label: 'Department',
                  value: student.department ?? 'Not provided'),
              _ProfileField(
                  label: 'Year group',
                  value: student.yearGroup?.toString() ?? 'Not provided'),
              _ProfileField(
                label: 'Interests',
                value: student.interests.isEmpty
                    ? 'Not provided'
                    : student.interests.join(', '),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.logout, color: AppColors.clay),
                title: const Text(
                  'Sign out',
                  style: TextStyle(color: AppColors.clay),
                ),
                trailing: signingOut
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : null,
                onTap: signingOut ? null : _signOut,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ProfileField extends StatelessWidget {
  const _ProfileField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: const Icon(Icons.badge_outlined),
        title: Text(label),
        subtitle: Text(value),
      );
}
