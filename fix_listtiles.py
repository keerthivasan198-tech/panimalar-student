import io
import os

def exact_replace(filepath, old, new):
    with open(filepath, 'r', encoding='utf-8') as f:
        text = f.read()
    if old in text:
        text = text.replace(old, new)
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(text)
        print(f'Replaced in {filepath}')
    else:
        print(f'Could not find text in {filepath}')

old1 = '''                            return ListTile(
                              leading: const Icon(Icons.directions_bus, color: Color(0xFF2563EB)),
                              title: Text(r.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              subtitle: Text(r.stops.take(3).join(', ') + '...', style: const TextStyle(fontSize: 11)),
                              onTap: () {
                                setState(() {
                                  _selectedLiveRoute = r;
                                  _liveMapSearchQuery = "";
                                  _liveMapSearchCtrl.text = r.name;
                                  
                                  // Optional: Center map on first stop of the route
                                  if (r.stops.isNotEmpty && coordsConfig[r.stops[0]] != null) {
                                    _mapController.move(coordsConfig[r.stops[0]]!, 12.0);
                                  }
                                });
                              },
                            );'''

new1 = '''                            return Material(
                              color: Colors.transparent,
                              child: ListTile(
                                leading: const Icon(Icons.directions_bus, color: Color(0xFF2563EB)),
                                title: Text(r.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                subtitle: Text(r.stops.take(3).join(', ') + '...', style: const TextStyle(fontSize: 11)),
                                onTap: () {
                                  setState(() {
                                    _selectedLiveRoute = r;
                                    _liveMapSearchQuery = "";
                                    _liveMapSearchCtrl.text = r.name;
                                    
                                    // Optional: Center map on first stop of the route
                                    if (r.stops.isNotEmpty && coordsConfig[r.stops[0]] != null) {
                                      _mapController.move(coordsConfig[r.stops[0]]!, 12.0);
                                    }
                                  });
                                },
                              ),
                            );'''

exact_replace('lib/screens/admin/admin_dashboard.dart', old1, new1)

old2 = '''                            return ListTile(
                              tileColor: isSelected ? const Color(0xFFF0F2F5) : Colors.white,
                              leading: const CircleAvatar(
                                backgroundColor: Color(0xFFDFE5E7),
                                child: Icon(Icons.person, color: Colors.white),
                              ),
                              title: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text("Route $bus", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87)),
                                  const Icon(Icons.circle, size: 10, color: Color(0xFF25D366)),
                                ],
                              ),
                              subtitle: Text(
                                lastMsg,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13, color: Colors.grey),
                              ),
                              onTap: () => setState(() => _selectedIntercomBus = bus),
                            );'''

new2 = '''                            return Material(
                              color: Colors.transparent,
                              child: ListTile(
                                tileColor: isSelected ? const Color(0xFFF0F2F5) : Colors.white,
                                leading: const CircleAvatar(
                                  backgroundColor: Color(0xFFDFE5E7),
                                  child: Icon(Icons.person, color: Colors.white),
                                ),
                                title: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text("Route $bus", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87)),
                                    const Icon(Icons.circle, size: 10, color: Color(0xFF25D366)),
                                  ],
                                ),
                                subtitle: Text(
                                  lastMsg,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13, color: Colors.grey),
                                ),
                                onTap: () => setState(() => _selectedIntercomBus = bus),
                              ),
                            );'''

exact_replace('lib/screens/admin/admin_dashboard.dart', old2, new2)

old3 = '''                            return ListTile(
                              dense: true,
                              title: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                              trailing: _selectedRoute == key ? const Icon(Icons.check_circle, color: Colors.green, size: 18) : null,
                              onTap: () {
                                _changeSelectedRoute(key);
                                _routeSearchCtrl.clear();
                                setState(() => _routeSearchQuery = "");
                                Navigator.pop(context); // Close dialog
                              },
                            );'''

new3 = '''                            return Material(
                              color: Colors.transparent,
                              child: ListTile(
                                dense: true,
                                title: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                                trailing: _selectedRoute == key ? const Icon(Icons.check_circle, color: Colors.green, size: 18) : null,
                                onTap: () {
                                  _changeSelectedRoute(key);
                                  _routeSearchCtrl.clear();
                                  setState(() => _routeSearchQuery = "");
                                  Navigator.pop(context); // Close dialog
                                },
                              ),
                            );'''

exact_replace('lib/screens/student/student_shell.dart', old3, new3)

old4 = '''                      child: ListTile(
                        title: Text(msg, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFF334155))),
                        trailing: const Icon(Icons.send_rounded, color: Color(0xFF2563EB), size: 18),
                        onTap: () {
                          _sendTextMessage(msg);
                          Navigator.pop(ctx);
                        },
                      ),'''

new4 = '''                      child: Material(
                        color: Colors.transparent,
                        child: ListTile(
                          title: Text(msg, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFF334155))),
                          trailing: const Icon(Icons.send_rounded, color: Color(0xFF2563EB), size: 18),
                          onTap: () {
                            _sendTextMessage(msg);
                            Navigator.pop(ctx);
                          },
                        ),
                      ),'''

exact_replace('lib/screens/driver/driver_dashboard.dart', old4, new4)
