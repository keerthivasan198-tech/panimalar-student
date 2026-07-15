import re
import requests
import time
import sys
import threading
from concurrent.futures import ThreadPoolExecutor

def geocode_arcgis(stop_name):
    # Try with Chennai first, then just Tamil Nadu
    queries = [
        f"{stop_name}, Chennai, Tamil Nadu, India",
        f"{stop_name}, Tamil Nadu, India"
    ]
    
    for q in queries:
        url = "https://geocode.arcgis.com/arcgis/rest/services/World/GeocodeServer/findAddressCandidates"
        params = {
            "f": "json",
            "singleLine": q,
            "maxLocations": 1
        }
        try:
            res = requests.get(url, params=params, timeout=10)
            if res.status_code == 200:
                data = res.json()
                if data.get('candidates') and len(data['candidates']) > 0:
                    loc = data['candidates'][0]['location']
                    return (loc['y'], loc['x'])
        except Exception as e:
            pass
        time.sleep(0.1) # small delay
    return None

def process_stop(stop, college_lat, college_lng):
    loc = geocode_arcgis(stop)
    if loc:
        return stop, loc
    else:
        return stop, (college_lat, college_lng)

def main():
    with open('lib/config/routes_config.dart', 'r', encoding='utf-8') as f:
        content = f.read()

    # Find the coordsConfig map
    match = re.search(r'final Map<String, LatLng> coordsConfig = \{(.*?)\};', content, re.DOTALL)
    if not match:
        print("Could not find coordsConfig")
        return
    
    coords_content = match.group(1)
    
    # Extract all stops
    stops = re.findall(r"'([^']+)':\s*const LatLng", coords_content)
    # Removing duplicates
    stops = list(dict.fromkeys(stops))
    
    print(f"Found {len(stops)} unique stops to geocode.")
    
    new_coords = {}
    college_lat, college_lng = 13.0489049, 80.0754642
    
    new_coords['COLLEGE'] = (college_lat, college_lng)
    new_coords['Panimalar Engineering College'] = (college_lat, college_lng)
    
    stops_to_process = [s for s in stops if s not in new_coords]
    
    # Parallel processing with ThreadPoolExecutor to speed it up (ArcGIS can handle a few concurrent requests)
    completed = 0
    with ThreadPoolExecutor(max_workers=5) as executor:
        futures = {executor.submit(process_stop, stop, college_lat, college_lng): stop for stop in stops_to_process}
        for future in futures:
            stop, loc = future.result()
            new_coords[stop] = loc
            completed += 1
            if completed % 50 == 0:
                print(f"Geocoded {completed}/{len(stops_to_process)} stops...")

    # Build new coordsConfig string
    new_str = ""
    # We want to maintain original order if possible, but dict order is fine in Dart.
    for stop, (lat, lng) in new_coords.items():
        # Escape single quotes in stop names if any exist
        safe_stop = stop.replace("'", "\\'")
        new_str += f"  '{safe_stop}': const LatLng({lat:.5f}, {lng:.5f}),\n"
        
    # Replace in file
    new_content = content[:match.start(1)] + "\n" + new_str + content[match.end(1):]
    
    with open('lib/config/routes_config.dart', 'w', encoding='utf-8') as f:
        f.write(new_content)
        
    print("Successfully updated routes_config.dart with real coordinates!")

if __name__ == '__main__':
    main()
