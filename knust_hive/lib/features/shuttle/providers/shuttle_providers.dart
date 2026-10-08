import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/services/supabase_service.dart';
import '../../../models/models.dart';

/// Streams live shuttle sightings from Supabase Realtime. Because this
/// is a `.stream()`, every device that has the app open sees a new
/// sighting within ~1s of it being posted — no polling required.
final shuttleReportsProvider = StreamProvider<List<ShuttleReport>>((ref) {
  return SupabaseService.client
      .from('shuttle_reports')
      .stream(primaryKey: ['id'])
      .order('created_at', ascending: false)
      .limit(60)
      .map((rows) => rows.map(ShuttleReport.fromMap).toList());
});

final ridePostsProvider = StreamProvider<List<RidePost>>((ref) {
  return SupabaseService.client
      .from('ride_posts')
      .stream(primaryKey: ['id'])
      .order('created_at', ascending: false)
      .limit(100)
      .map((rows) => rows.map(RidePost.fromMap).toList());
});

final liveShuttleLocationsProvider =
    StreamProvider<List<LiveShuttleLocation>>((ref) {
  return SupabaseService.client
      .from('live_shuttle_locations')
      .stream(primaryKey: ['vehicle_id'])
      .order('updated_at', ascending: false)
      .limit(50)
      .map(
        (rows) => rows
            .where((row) => row['is_active'] == true)
            .map(LiveShuttleLocation.fromMap)
            .toList(),
      );
});

class ShuttleActions {
  final _client = SupabaseService.client;

  Future<void> reportSighting(
      {required String stopId, required String route}) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('Must be signed in to report a sighting');
    }
    await _client.from('shuttle_reports').insert({
      'id': const Uuid().v4(),
      'stop_id': stopId,
      'route': route,
      'reported_by': userId,
    });
    // A Supabase Edge Function (see supabase/functions/notify_nearby)
    // listens for inserts on this table and pushes a notification to
    // students who favorited stops near this one.
  }

  Future<void> postRide({
    required RidePostType type,
    required String fromStopId,
    required String toStopId,
    required String time,
    String? note,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw StateError('Must be signed in to post');
    await _client.from('ride_posts').insert({
      'id': const Uuid().v4(),
      'type': type.name,
      'from_stop_id': fromStopId,
      'to_stop_id': toStopId,
      'time_label': time,
      'note': note,
      'posted_by': userId,
    });
  }

  Future<void> deleteRidePost(String id) async {
    await _client.from('ride_posts').delete().eq('id', id);
  }
}

final shuttleActionsProvider = Provider((ref) => ShuttleActions());
