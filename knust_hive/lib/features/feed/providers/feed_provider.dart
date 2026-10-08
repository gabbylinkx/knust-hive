import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/services/supabase_service.dart';
import '../../../models/models.dart';

final feedProvider = StreamProvider<List<FeedPost>>((ref) {
  return SupabaseService.client
      .from('feed_posts')
      .stream(primaryKey: ['id'])
      .order('created_at', ascending: false)
      .limit(100)
      .map((rows) => rows.map(FeedPost.fromMap).toList());
});

class FeedActions {
  final _client = SupabaseService.client;

  Future<void> post(
      {required FeedCategory category, required String text}) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw StateError('Sign in to post');
    await _client.from('feed_posts').insert({
      'id': const Uuid().v4(),
      'category': category.name,
      'text': text,
      'posted_by': userId,
    });
  }

  Future<void> delete(String id) =>
      _client.from('feed_posts').delete().eq('id', id);
}

final feedActionsProvider = Provider((ref) => FeedActions());
