
import 'dart:math';

class LatLng {
  final double latitude;
  final double longitude;
  const LatLng(this.latitude, this.longitude);
}

class _Node {
  final String id;
  final LatLng pos;
  const _Node(this.id, this.pos);
}

final _nodes = <_Node>[
  _Node('gate',         const LatLng(13.04723, 80.07553)),
  _Node('gate_n',       const LatLng(13.04790, 80.07548)),
  _Node('admin_jct',    const LatLng(13.04885, 80.07541)), 
  _Node('cse_w',        const LatLng(13.04960, 80.07465)), 
  _Node('cse_jct',      const LatLng(13.04968, 80.07533)), 
  _Node('cse_e',        const LatLng(13.04975, 80.07610)), 
  _Node('aids_jct',     const LatLng(13.04980, 80.07646)), 
  _Node('east_lane_mid',const LatLng(13.05075, 80.07648)), 
  _Node('spine_a',      const LatLng(13.05020, 80.07510)),
  _Node('spine_b',      const LatLng(13.05085, 80.07490)), 
  _Node('spine_c',      const LatLng(13.05090, 80.07525)), 
  _Node('spine_d',      const LatLng(13.05130, 80.07510)),
  _Node('spine_e',      const LatLng(13.05172, 80.07520)), 
  _Node('csbs_w',       const LatLng(13.05172, 80.07520)), 
  _Node('csbs_mid',     const LatLng(13.05172, 80.07575)),
  _Node('csbs_jct',     const LatLng(13.05172, 80.07600)), 
  _Node('csbs_e',       const LatLng(13.05172, 80.07650)), 
  _Node('mid_n1',       const LatLng(13.05240, 80.07510)),
  _Node('mid_n2',       const LatLng(13.05310, 80.07500)), 
  _Node('mess2_jct',    const LatLng(13.05352, 80.07515)), 
  _Node('mba_jct',      const LatLng(13.05391, 80.07534)), 
  _Node('it_road_s',    const LatLng(13.05340, 80.07410)),
  _Node('it_jct',       const LatLng(13.05348, 80.07340)), 
  _Node('north_jct',    const LatLng(13.05410, 80.07340)), 
  _Node('eee_road',     const LatLng(13.05459, 80.07300)),
  _Node('eee_jct',      const LatLng(13.05459, 80.07269)), 
  _Node('mech_jct',     const LatLng(13.05474, 80.07274)), 
  _Node('mess1_jct',    const LatLng(13.05085, 80.07474)), 
];

final _edges = [
  ['gate',      'gate_n'],
  ['gate_n',    'admin_jct'],
  ['admin_jct', 'cse_jct'],
  ['admin_jct', 'cse_w'],
  ['cse_w',     'cse_jct'],
  ['cse_jct',   'cse_e'],
  ['cse_e',     'aids_jct'],
  ['cse_w',     'spine_a'],
  ['cse_jct',   'spine_a'],
  ['spine_a',   'spine_b'],
  ['spine_b',   'spine_c'],
  ['spine_c',   'spine_d'],
  ['spine_d',   'spine_e'],
  ['spine_c',   'spine_c'], 
  ['spine_b',   'mess1_jct'],
  ['spine_e',   'csbs_mid'],
  ['csbs_mid',  'csbs_jct'],
  ['csbs_jct',  'csbs_e'],
  ['spine_e',   'mid_n1'],
  ['mid_n1',    'mid_n2'],
  ['mid_n2',    'mess2_jct'],
  ['mess2_jct', 'mba_jct'],
  ['mid_n1',    'it_road_s'],
  ['it_road_s', 'it_jct'],
  ['it_jct',    'north_jct'],
  ['north_jct', 'eee_road'],
  ['eee_road',  'eee_jct'],
  ['eee_jct',   'mech_jct'],
  ['csbs_e',    'mid_n2'],   
  ['mba_jct',   'it_road_s'],
  ['aids_jct',  'east_lane_mid'],
  ['east_lane_mid', 'csbs_e'],
];

const _buildingSnap = <String, String>{
  'Main Entrance Gate':       'gate',
  'Admin / Admission Block':  'admin_jct',
  'CSE Department':           'cse_jct',
  'AIDS (AI & Data Sci.)':    'aids_jct',
  'ECE Department':           'spine_c',
  'EEE Department':           'eee_jct',
  'IT Department':            'it_jct',
  'CSBS Department':          'csbs_jct',
  'Mechanical Dept.':         'mech_jct',
  'MBA Block':                'mba_jct',
  'Mess 1 (Main Mess)':       'mess1_jct',
  'Mess 2 (Hostel Mess)':     'mess2_jct',
};

class CampusPathGraph {
  late final Map<String, _Node> _nodeMap;
  late final Map<String, List<String>> _adj;

  CampusPathGraph() {
    _nodeMap = {for (final n in _nodes) n.id: n};
    _adj = {};
    for (final n in _nodes) {
      _adj[n.id] = [];
    }

    for (final e in _edges) {
      final a = e[0], b = e[1];
      if (a == b) continue;
      if (!_adj.containsKey(a) || !_adj.containsKey(b)) continue;
      if (!_adj[a]!.contains(b)) _adj[a]!.add(b);
      if (!_adj[b]!.contains(a)) _adj[b]!.add(a);
    }
  }

  double _dist(LatLng a, LatLng b) {
    const r = 6371000.0;
    final p1 = a.latitude  * (pi / 180);
    final p2 = b.latitude  * (pi / 180);
    final dp = (b.latitude  - a.latitude)  * (pi / 180);
    final dl = (b.longitude - a.longitude) * (pi / 180);
    final x  = sin(dp / 2) * sin(dp / 2) +
               cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2);
    return r * 2 * atan2(sqrt(x), sqrt(1 - x));
  }

  String _snap(LatLng pos) {
    String best = _nodes.first.id;
    double bestD = double.infinity;
    for (final n in _nodes) {
      final d = _dist(pos, n.pos);
      if (d < bestD) { bestD = d; best = n.id; }
    }
    return best;
  }

  String _snapBuilding(String name, LatLng fallback) =>
      _buildingSnap[name] ?? _snap(fallback);

  List<LatLng> shortestPath(LatLng origin, LatLng destination,
      {String? destName}) {
    final startId = _snap(origin);
    final endId   = destName != null
        ? _snapBuilding(destName, destination)
        : _snap(destination);

    if (startId == endId) return [origin, _nodeMap[startId]!.pos, destination];

    final dist = <String, double>{
      for (final n in _nodes) n.id: double.infinity,
    };
    final prev = <String, String?>{for (final n in _nodes) n.id: null};
    dist[startId] = 0;

    final unvisited = <String>{for (final n in _nodes) n.id};

    while (unvisited.isNotEmpty) {
      String? u;
      double minD = double.infinity;
      for (final id in unvisited) {
        if (dist[id]! < minD) { minD = dist[id]!; u = id; }
      }
      if (u == null || u == endId) break;
      unvisited.remove(u);

      for (final v in (_adj[u] ?? [])) {
        if (!unvisited.contains(v)) continue;
        final alt = dist[u]! + _dist(_nodeMap[u]!.pos, _nodeMap[v]!.pos);
        if (alt < dist[v]!) {
          dist[v] = alt;
          prev[v] = u;
        }
      }
    }

    final ids = <String>[];
    String? cur = endId;
    while (cur != null) { ids.add(cur); cur = prev[cur]; }
    final ordered = ids.reversed.toList();

    if (ordered.isEmpty || ordered.first != startId) {
      print('FAILED TO FIND PATH FROM  TO \');
      return [origin, destination]; 
    }

    final path = <LatLng>[origin];
    for (final id in ordered) {
      path.add(_nodeMap[id]!.pos);
    }
    path.add(destination);
    return path;
  }
}

void main() {
  final g = CampusPathGraph();
  final path = g.shortestPath(LatLng(13.050841, 80.074740), LatLng(13.05172, 80.07600), destName: 'CSBS Department');
  print('Path length: \');
}

