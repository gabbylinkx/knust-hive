import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/models.dart';
import '../campus_stops.dart';
import '../providers/shuttle_providers.dart';

class ShuttleScreen extends ConsumerStatefulWidget {
  const ShuttleScreen({super.key});

  @override
  ConsumerState<ShuttleScreen> createState() => _ShuttleScreenState();
}

class _ShuttleScreenState extends ConsumerState<ShuttleScreen> {
  String selectedStopId = greenStops.first.id;
  RidePostType boardTab = RidePostType.need;
  Timer? freshnessTimer;

  @override
  void initState() {
    super.initState();
    freshnessTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    freshnessTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reportsAsync = ref.watch(shuttleReportsProvider);
    final ridesAsync = ref.watch(ridePostsProvider);
    final liveLocationsAsync = ref.watch(liveShuttleLocationsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Shuttle tracker')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _RouteMapCard(locationsAsync: liveLocationsAsync),
          const SizedBox(height: 12),
          const _DriverLocationPanel(),
          const SizedBox(height: 16),
          _ReportBar(
            selectedStopId: selectedStopId,
            onStopChanged: (id) => setState(() => selectedStopId = id),
            onReport: () async {
              try {
                await ref.read(shuttleActionsProvider).reportSighting(
                      stopId: selectedStopId,
                      route: greenStops.any((s) => s.id == selectedStopId)
                          ? 'green'
                          : 'gold',
                    );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text(
                            'Logged a shuttle at ${stopById(selectedStopId).name}')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Could not report sighting: $e')),
                  );
                }
              }
            },
          ),
          const SizedBox(height: 20),
          Text('Recent sightings',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          reportsAsync.when(
            data: (reports) {
              final fresh = reports.where((r) => r.isFresh).toList();
              if (fresh.isEmpty) {
                return const _EmptyHint('No sightings in the last 30 minutes.');
              }
              return Column(
                children:
                    fresh.take(8).map((r) => _SightingTile(report: r)).toList(),
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Text('Couldn\'t load sightings: $e'),
          ),
          const SizedBox(height: 24),
          _RideBoard(
            ridesAsync: ridesAsync,
            tab: boardTab,
            onTabChanged: (t) => setState(() => boardTab = t),
          ),
        ],
      ),
    );
  }
}

class _RouteMapCard extends StatelessWidget {
  final AsyncValue<List<LiveShuttleLocation>> locationsAsync;
  const _RouteMapCard({required this.locationsAsync});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Live shuttle locations',
                    style: Theme.of(context).textTheme.titleMedium),
                const Row(children: [
                  _LegendDot(color: AppColors.forestLight, label: 'Green'),
                  SizedBox(width: 10),
                  _LegendDot(color: AppColors.gold, label: 'Gold'),
                ]),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 320,
              child: locationsAsync.when(
                data: (locations) {
                  final live = locations.where((item) => item.isFresh).toList();
                  return FlutterMap(
                    options: const MapOptions(
                      initialCenter: LatLng(6.6745, -1.5650),
                      initialZoom: 14.5,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.knusthive.app',
                      ),
                      MarkerLayer(
                        markers: [
                          for (final vehicle in live)
                            Marker(
                              point:
                                  LatLng(vehicle.latitude, vehicle.longitude),
                              width: 116,
                              height: 48,
                              alignment: Alignment.topCenter,
                              child: Tooltip(
                                message:
                                    '${vehicle.label} · ${vehicle.route.name.toUpperCase()} route',
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: vehicle.route == ShuttleRoute.green
                                        ? AppColors.forest
                                        : AppColors.gold,
                                    borderRadius: BorderRadius.circular(22),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Colors.black26,
                                        blurRadius: 5,
                                      ),
                                    ],
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 6),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.directions_bus,
                                          color: Colors.white, size: 18),
                                      const SizedBox(width: 5),
                                      Flexible(
                                        child: Text(
                                          vehicle.label,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      RichAttributionWidget(
                        attributions: [
                          TextSourceAttribution(
                            '© OpenStreetMap contributors',
                            onTap: () => launchUrl(
                              Uri.parse(
                                  'https://www.openstreetmap.org/copyright'),
                              mode: LaunchMode.externalApplication,
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child:
                        Text('Could not load live vehicle locations: $error'),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              locationsAsync.maybeWhen(
                data: (locations) {
                  final live = locations.where((item) => item.isFresh).length;
                  return live == 0
                      ? 'No shuttle is broadcasting a fresh GPS location right now.'
                      : '$live shuttle${live == 1 ? '' : 's'} broadcasting live · updates every few seconds';
                },
                orElse: () =>
                    'Vehicle positions are streamed from approved shuttle operators.',
              ),
              style: const TextStyle(fontSize: 11.5, color: Color(0xFF5B6355)),
            ),
          ],
        ),
      ),
    );
  }
}

class _DriverLocationPanel extends StatefulWidget {
  const _DriverLocationPanel();

  @override
  State<_DriverLocationPanel> createState() => _DriverLocationPanelState();
}

class _DriverLocationPanelState extends State<_DriverLocationPanel> {
  late final Future<Map<String, dynamic>?> operatorAssignment =
      _loadAssignment();
  StreamSubscription<Position>? positionSubscription;
  bool tracking = false;
  bool busy = false;

  Future<Map<String, dynamic>?> _loadAssignment() async {
    final client = SupabaseService.client;
    final rows = await client
        .from('shuttle_operators')
        .select('vehicle_id, label, route')
        .eq('user_id', client.auth.currentUser!.id)
        .eq('is_active', true)
        .limit(1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> _publish(
    Map<String, dynamic> assignment,
    Position position, {
    required bool active,
  }) async {
    await SupabaseService.client.from('live_shuttle_locations').upsert(
      {
        'vehicle_id': assignment['vehicle_id'],
        'label': assignment['label'],
        'route': assignment['route'],
        'latitude': position.latitude,
        'longitude': position.longitude,
        'heading': position.heading.isFinite ? position.heading : null,
        'speed_meters_per_second':
            position.speed.isFinite && position.speed >= 0
                ? position.speed
                : null,
        'is_active': active,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      onConflict: 'vehicle_id',
    );
  }

  Future<void> _startTracking(Map<String, dynamic> assignment) async {
    setState(() => busy = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw StateError('Turn on location services, then try again.');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        throw StateError('Location permission is required to share this bus.');
      }
      if (permission == LocationPermission.deniedForever) {
        throw StateError(
            'Location access is blocked. Allow it in your browser or device settings.');
      }

      const settings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      );
      final firstPosition = await Geolocator.getCurrentPosition(
        locationSettings: settings,
      );
      if (firstPosition.accuracy > 100) {
        throw StateError(
            'GPS accuracy is too low (${firstPosition.accuracy.round()} m). Move to an open area and retry.');
      }
      await _publish(assignment, firstPosition, active: true);
      positionSubscription =
          Geolocator.getPositionStream(locationSettings: settings).listen(
        (position) {
          if (position.accuracy > 100) return;
          _publish(assignment, position, active: true).catchError((error) {
            _showError('Could not publish live location: $error');
          });
        },
        onError: (Object error) {
          _showError('Location tracking stopped: $error');
          unawaited(_stopTracking(assignment));
        },
      );
      if (mounted) setState(() => tracking = true);
    } catch (error) {
      try {
        final position = await Geolocator.getLastKnownPosition();
        if (position != null) {
          await _publish(assignment, position, active: false);
        }
      } catch (_) {
        // Keep the original location error for the user.
      }
      _showError('Could not start GPS sharing: $error');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _stopTracking(Map<String, dynamic> assignment) async {
    final subscription = positionSubscription;
    positionSubscription = null;
    await subscription?.cancel();
    try {
      final position = await Geolocator.getLastKnownPosition();
      if (position != null) {
        await _publish(assignment, position, active: false);
      } else {
        await SupabaseService.client.from('live_shuttle_locations').update({
          'is_active': false,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('vehicle_id', assignment['vehicle_id']);
      }
    } catch (error) {
      _showError('GPS stopped, but could not update its status: $error');
    } finally {
      if (mounted) setState(() => tracking = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    positionSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: operatorAssignment,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Card(
            child: ListTile(
              leading: const Icon(Icons.error_outline),
              title: Text('Could not check driver access: ${snapshot.error}'),
            ),
          );
        }
        if (snapshot.data == null) {
          return const Card(
            child: ListTile(
              dense: true,
              leading: Icon(Icons.gps_fixed),
              title: Text('Live GPS is shared by approved shuttle operators.'),
            ),
          );
        }
        final assignment = snapshot.data!;
        return Card(
          child: ListTile(
            leading: Icon(
              tracking ? Icons.gps_fixed : Icons.gps_not_fixed,
              color: tracking ? AppColors.forest : AppColors.clay,
            ),
            title: Text('${assignment['label']} · driver mode'),
            subtitle: Text(
              tracking
                  ? 'Sharing your GPS on the ${assignment['route']} route'
                  : 'Start sharing only while driving this shuttle.',
            ),
            trailing: busy
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : FilledButton(
                    onPressed: () => tracking
                        ? _stopTracking(assignment)
                        : _startTracking(assignment),
                    child: Text(tracking ? 'Stop' : 'Start'),
                  ),
          ),
        );
      },
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 12, height: 3, color: color),
      const SizedBox(width: 4),
      Text(label,
          style: const TextStyle(fontSize: 11.5, color: Color(0xFF5B6355))),
    ]);
  }
}

class _ReportBar extends StatelessWidget {
  final String selectedStopId;
  final ValueChanged<String> onStopChanged;
  final VoidCallback onReport;
  const _ReportBar(
      {required this.selectedStopId,
      required this.onStopChanged,
      required this.onReport});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: AppColors.forest, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          const Icon(Icons.place, color: AppColors.gold, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: selectedStopId,
                isExpanded: true,
                dropdownColor: Colors.white,
                items: allStops
                    .map((s) =>
                        DropdownMenuItem(value: s.id, child: Text(s.name)))
                    .toList(),
                onChanged: (v) => v != null ? onStopChanged(v) : null,
              ),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: onReport,
            icon: const Icon(Icons.near_me, size: 16),
            label: const Text('Report'),
          ),
        ],
      ),
    );
  }
}

class _SightingTile extends StatelessWidget {
  final ShuttleReport report;
  const _SightingTile({required this.report});

  @override
  Widget build(BuildContext context) {
    final mins = DateTime.now().difference(report.ts).inMinutes;
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        leading:
            const Icon(Icons.directions_bus, color: AppColors.forest, size: 18),
        title: Text(stopById(report.stopId).name),
        trailing: Text(mins < 1 ? 'just now' : '${mins}m ago',
            style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11.5,
                color: Color(0xFF5B6355))),
      ),
    );
  }
}

class _RideBoard extends ConsumerWidget {
  final AsyncValue<List<RidePost>> ridesAsync;
  final RidePostType tab;
  final ValueChanged<RidePostType> onTabChanged;
  const _RideBoard(
      {required this.ridesAsync,
      required this.tab,
      required this.onTabChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Ride board',
                    style: Theme.of(context).textTheme.titleMedium),
                TextButton.icon(
                  onPressed: () => _showPostSheet(context, ref, tab),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Post'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: _TabChip(
                  label: 'Need a ride',
                  selected: tab == RidePostType.need,
                  onTap: () => onTabChanged(RidePostType.need),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _TabChip(
                  label: 'Offering space',
                  selected: tab == RidePostType.offer,
                  onTap: () => onTabChanged(RidePostType.offer),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            ridesAsync.when(
              data: (rides) {
                final visible = rides.where((p) => p.type == tab).toList();
                if (visible.isEmpty) {
                  return const _EmptyHint('Nothing posted yet.');
                }
                return Column(
                  children: visible.map((p) => _RidePostTile(post: p)).toList(),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('Couldn\'t load ride board: $e'),
            ),
          ],
        ),
      ),
    );
  }

  void _showPostSheet(BuildContext context, WidgetRef ref, RidePostType type) {
    String from = greenStops.first.id;
    String to = hub.id;
    final timeCtrl = TextEditingController();
    final noteCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
        ),
        child: StatefulBuilder(
          builder: (ctx, setSheetState) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(type == RidePostType.need ? 'Need a ride' : 'Offer space',
                  style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: from,
                    items: allStops
                        .map((s) =>
                            DropdownMenuItem(value: s.id, child: Text(s.name)))
                        .toList(),
                    onChanged: (v) => setSheetState(() => from = v ?? from),
                  ),
                ),
                const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(Icons.arrow_forward, size: 16)),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: to,
                    items: allStops
                        .map((s) =>
                            DropdownMenuItem(value: s.id, child: Text(s.name)))
                        .toList(),
                    onChanged: (v) => setSheetState(() => to = v ?? to),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              TextField(
                  controller: timeCtrl,
                  decoration: const InputDecoration(
                      hintText: 'When? e.g. Today 4:30pm')),
              const SizedBox(height: 8),
              TextField(
                  controller: noteCtrl,
                  decoration:
                      const InputDecoration(hintText: 'Note (optional)')),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    if (timeCtrl.text.trim().isEmpty || from == to) return;
                    try {
                      await ref.read(shuttleActionsProvider).postRide(
                            type: type,
                            fromStopId: from,
                            toStopId: to,
                            time: timeCtrl.text.trim(),
                            note: noteCtrl.text.trim().isEmpty
                                ? null
                                : noteCtrl.text.trim(),
                          );
                      if (ctx.mounted) Navigator.pop(ctx);
                    } catch (error) {
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(
                              content: Text('Could not post ride: $error')),
                        );
                      }
                    }
                  },
                  child: const Text('Post to board'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _TabChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.forest : Colors.white,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
              color: selected ? AppColors.forest : AppColors.paperDim,
              width: 1.5),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : AppColors.ink)),
      ),
    );
  }
}

class _RidePostTile extends ConsumerWidget {
  final RidePost post;
  const _RidePostTile({required this.post});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mins = DateTime.now().difference(post.ts).inMinutes;
    final isOwner =
        SupabaseService.client.auth.currentUser?.id == post.postedBy;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                      '${stopById(post.fromStopId).name}  →  ${stopById(post.toStopId).name}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13.5)),
                ),
                if (isOwner)
                  IconButton(
                    tooltip: 'Delete ride post',
                    icon: const Icon(Icons.delete_outline, size: 18),
                    onPressed: () async {
                      try {
                        await ref
                            .read(shuttleActionsProvider)
                            .deleteRidePost(post.id);
                      } catch (error) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Could not delete ride: $error'),
                            ),
                          );
                        }
                      }
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  )
                else
                  IconButton(
                    tooltip: 'Contact student',
                    icon: const Icon(Icons.chat_bubble_outline, size: 18),
                    onPressed: () async {
                      try {
                        final chatId = await SupabaseService.client.rpc(
                          'create_direct_chat',
                          params: {'target_user': post.postedBy},
                        );
                        if (context.mounted) {
                          await context.push(
                            '/chat/$chatId?title=${Uri.encodeQueryComponent('Ride post')}',
                          );
                        }
                      } catch (error) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content:
                                    Text('Could not contact student: $error')),
                          );
                        }
                      }
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(spacing: 10, children: [
              Text(post.time,
                  style:
                      const TextStyle(fontSize: 12, color: Color(0xFF5B6355))),
              Text('${mins}m ago',
                  style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: Color(0xFF5B6355))),
            ]),
            if (post.note != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(post.note!, style: const TextStyle(fontSize: 12.5)),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final String text;
  const _EmptyHint(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.paperDim, style: BorderStyle.solid),
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: Text(text,
          style: const TextStyle(fontSize: 13, color: Color(0xFF5B6355))),
    );
  }
}
