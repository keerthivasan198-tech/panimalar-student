
import 'package:http/http.dart' as http;

void main() async {
  final url = 'http://router.project-osrm.org/route/v1/foot/80.07600,13.05172;80.07474,13.05085?geometries=geojson';
  final response = await http.get(Uri.parse(url));
  print(response.statusCode);
  print(response.body);
}

