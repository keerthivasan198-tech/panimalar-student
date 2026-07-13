class RouteEntry {
  final double id;
  final String key;
  final String name;
  final List<String> stops;
  final String color;

  RouteEntry({
    required this.id,
    required this.key,
    required this.name,
    required this.stops,
    required this.color,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'key': key,
    'name': name,
    'stops': stops,
    'color': color,
  };

  factory RouteEntry.fromJson(Map<String, dynamic> json) => RouteEntry(
    id: (json['id'] as num).toDouble(),
    key: json['key'] ?? '',
    name: json['name'] ?? '',
    stops: List<String>.from(json['stops'] ?? []),
    color: json['color'] ?? '#2563EB',
  );
}
