import 'package:flutter_test/flutter_test.dart';
import 'package:knust_hive/models/models.dart';

void main() {
  group('FeedPost', () {
    test('parses category, content, author and timestamp from Supabase', () {
      final createdAt = DateTime.utc(2026, 10, 8);
      final post = FeedPost.fromMap({
        'id': 'post-1',
        'category': 'studyGroup',
        'text': 'Study group at the library',
        'posted_by': 'student-1',
        'created_at': createdAt.toIso8601String(),
        'rsvp_count': 3,
      });

      expect(post.id, 'post-1');
      expect(post.category, FeedCategory.studyGroup);
      expect(post.text, 'Study group at the library');
      expect(post.postedBy, 'student-1');
      expect(post.ts, createdAt);
      expect(post.rsvpCount, 3);
    });
  });

  group('ShuttleReport', () {
    test('parses route and reports freshness', () {
      final report = ShuttleReport.fromMap({
        'id': 'report-1',
        'stop_id': 'g1',
        'route': 'green',
        'reported_by': 'student-1',
        'created_at': DateTime.now()
            .subtract(const Duration(minutes: 2))
            .toIso8601String(),
      });

      expect(report.route, ShuttleRoute.green);
      expect(report.stopId, 'g1');
      expect(report.isFresh, isTrue);
    });
  });

  group('LiveShuttleLocation', () {
    test('parses a realtime location and expires stale coordinates', () {
      final location = LiveShuttleLocation.fromMap({
        'vehicle_id': 'green-01',
        'label': 'Green shuttle 01',
        'route': 'green',
        'latitude': 6.6745,
        'longitude': -1.565,
        'heading': 180,
        'speed_meters_per_second': 4.5,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'is_active': true,
      });

      expect(location.vehicleId, 'green-01');
      expect(location.route, ShuttleRoute.green);
      expect(location.latitude, 6.6745);
      expect(location.longitude, -1.565);
      expect(location.heading, 180);
      expect(location.speedMetersPerSecond, 4.5);
      expect(location.isFresh, isTrue);
    });
  });

  group('RidePost', () {
    test('parses ride details from Supabase', () {
      final createdAt = DateTime.utc(2026, 10, 8);
      final post = RidePost.fromMap({
        'id': 'ride-1',
        'type': 'offer',
        'from_stop_id': 'g1',
        'to_stop_id': 'hub',
        'time_label': 'Today at 4 pm',
        'note': 'Two seats',
        'posted_by': 'student-1',
        'created_at': createdAt.toIso8601String(),
      });

      expect(post.type, RidePostType.offer);
      expect(post.fromStopId, 'g1');
      expect(post.toStopId, 'hub');
      expect(post.time, 'Today at 4 pm');
      expect(post.note, 'Two seats');
      expect(post.ts, createdAt);
    });
  });
}
