class DriverEntry {
  final double id;
  final String bus;
  final String driver;
  final String contact;
  final String route;
  final String type; // boys, girls, combined
  final String password; // new field

  DriverEntry({
    required this.id,
    required this.bus,
    required this.driver,
    required this.contact,
    required this.route,
    required this.type,
    required this.password,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'bus': bus,
    'driver': driver,
    'contact': contact,
    'route': route,
    'type': type,
    'password': password,
  };

  factory DriverEntry.fromJson(Map<String, dynamic> json) => DriverEntry(
    id: (json['id'] as num).toDouble(),
    bus: json['bus'] ?? '',
    driver: json['driver'] ?? '',
    contact: json['contact'] ?? '',
    route: json['route'] ?? '',
    type: json['type'] ?? 'combined',
    password: json['password'] ?? '1234',
  );
}
