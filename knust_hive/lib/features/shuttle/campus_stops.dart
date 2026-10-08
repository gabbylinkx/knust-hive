class CampusStop {
  final String id;
  final String name;
  final double x; // schematic map coordinate, 0-800
  final double y; // schematic map coordinate, 0-500
  final bool isHub;

  const CampusStop(this.id, this.name, this.x, this.y, {this.isHub = false});
}

/// Schematic (non-GPS) transit-map layout, matching the web prototype.
/// Replace with real lat/lng once campus GPS survey data is available —
/// see supabase/schema.sql `stops` table for the geo-ready column.
const hub = CampusStop('hub', 'Commercial Area', 400, 250, isHub: true);

const greenStops = <CampusStop>[
  CampusStop('g0', 'Main Gate', 70, 250),
  CampusStop('g1', 'Republic Hall', 180, 250),
  CampusStop('g2', 'Katanga', 290, 250),
  hub,
  CampusStop('g3', 'Engineering', 510, 250),
  CampusStop('g4', 'Business School', 620, 250),
  CampusStop('g5', 'Conti Campus', 730, 250),
];

const goldStops = <CampusStop>[
  CampusStop('y0', 'Bomso Gate', 400, 60),
  CampusStop('y1', 'Ayeduase Gate', 400, 125),
  CampusStop('y2', 'Unity Hall', 400, 188),
  hub,
  CampusStop('y3', 'Africa Hall', 400, 312),
  CampusStop('y4', 'Queens Hall', 400, 378),
  CampusStop('y5', 'Univ. Hospital', 400, 442),
];

final allStops = <CampusStop>{...greenStops, ...goldStops}.toList()
  ..sort((a, b) => a.name.compareTo(b.name));

CampusStop stopById(String id) =>
    allStops.firstWhere((s) => s.id == id, orElse: () => hub);
