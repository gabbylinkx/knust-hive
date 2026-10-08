// Plain data models mapped 1:1 to Supabase tables (see supabase/schema.sql).
// Kept dependency-free so they can be reused by Riverpod providers,
// local Hive cache adapters, and widgets alike.

class UserProfile {
  final String id; // matches auth.users.id
  final String displayName;
  final String? faculty;
  final String? department;
  final int? yearGroup;
  final List<String> interests;
  final String? avatarUrl;

  UserProfile({
    required this.id,
    required this.displayName,
    this.faculty,
    this.department,
    this.yearGroup,
    this.interests = const [],
    this.avatarUrl,
  });

  factory UserProfile.fromMap(Map<String, dynamic> m) => UserProfile(
        id: m['id'] as String,
        displayName: m['display_name'] as String,
        faculty: m['faculty'] as String?,
        department: m['department'] as String?,
        yearGroup: m['year_group'] as int?,
        interests: (m['interests'] as List?)?.cast<String>() ?? const [],
        avatarUrl: m['avatar_url'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'display_name': displayName,
        'faculty': faculty,
        'department': department,
        'year_group': yearGroup,
        'interests': interests,
        'avatar_url': avatarUrl,
      };
}

enum ShuttleRoute { green, gold }

class LiveShuttleLocation {
  const LiveShuttleLocation({
    required this.vehicleId,
    required this.label,
    required this.route,
    required this.latitude,
    required this.longitude,
    required this.updatedAt,
    this.heading,
    this.speedMetersPerSecond,
  });

  final String vehicleId;
  final String label;
  final ShuttleRoute route;
  final double latitude;
  final double longitude;
  final DateTime updatedAt;
  final double? heading;
  final double? speedMetersPerSecond;

  factory LiveShuttleLocation.fromMap(Map<String, dynamic> map) =>
      LiveShuttleLocation(
        vehicleId: map['vehicle_id'] as String,
        label: map['label'] as String? ?? 'KNUST shuttle',
        route: ShuttleRoute.values
            .firstWhere((route) => route.name == map['route']),
        latitude: (map['latitude'] as num).toDouble(),
        longitude: (map['longitude'] as num).toDouble(),
        updatedAt: DateTime.parse(map['updated_at'] as String).toLocal(),
        heading: (map['heading'] as num?)?.toDouble(),
        speedMetersPerSecond:
            (map['speed_meters_per_second'] as num?)?.toDouble(),
      );

  bool get isFresh =>
      DateTime.now().difference(updatedAt) <= const Duration(seconds: 45);
}

class ShuttleReport {
  final String id;
  final String stopId;
  final ShuttleRoute route;
  final String reportedBy;
  final DateTime ts;

  ShuttleReport({
    required this.id,
    required this.stopId,
    required this.route,
    required this.reportedBy,
    required this.ts,
  });

  factory ShuttleReport.fromMap(Map<String, dynamic> m) => ShuttleReport(
        id: m['id'] as String,
        stopId: m['stop_id'] as String,
        route: ShuttleRoute.values.firstWhere((r) => r.name == m['route']),
        reportedBy: m['reported_by'] as String,
        ts: DateTime.parse(m['created_at'] as String),
      );

  bool get isFresh =>
      DateTime.now().difference(ts) < const Duration(minutes: 30);
}

enum RidePostType { need, offer }

class RidePost {
  final String id;
  final RidePostType type;
  final String fromStopId;
  final String toStopId;
  final String time;
  final String? note;
  final String postedBy;
  final DateTime ts;

  RidePost({
    required this.id,
    required this.type,
    required this.fromStopId,
    required this.toStopId,
    required this.time,
    this.note,
    required this.postedBy,
    required this.ts,
  });

  factory RidePost.fromMap(Map<String, dynamic> m) => RidePost(
        id: m['id'] as String,
        type: RidePostType.values.firstWhere((t) => t.name == m['type']),
        fromStopId: m['from_stop_id'] as String,
        toStopId: m['to_stop_id'] as String,
        time: m['time_label'] as String,
        note: m['note'] as String?,
        postedBy: m['posted_by'] as String,
        ts: DateTime.parse(m['created_at'] as String),
      );
}

enum FeedCategory { event, lostFound, shoutout, studyGroup }

class FeedPost {
  final String id;
  final FeedCategory category;
  final String text;
  final String postedBy;
  final DateTime ts;
  final int rsvpCount;

  FeedPost({
    required this.id,
    required this.category,
    required this.text,
    required this.postedBy,
    required this.ts,
    this.rsvpCount = 0,
  });

  factory FeedPost.fromMap(Map<String, dynamic> m) => FeedPost(
        id: m['id'] as String,
        category:
            FeedCategory.values.firstWhere((c) => c.name == m['category']),
        text: m['text'] as String,
        postedBy: m['posted_by'] as String,
        ts: DateTime.parse(m['created_at'] as String),
        rsvpCount: m['rsvp_count'] as int? ?? 0,
      );
}
