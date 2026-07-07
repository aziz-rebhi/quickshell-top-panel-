#!/usr/bin/env python3
import json, urllib.request, sys, os

def fetch(url, headers=None):
    try:
        req = urllib.request.Request(url, headers=headers or {})
        return json.loads(urllib.request.urlopen(req, timeout=3).read())
    except:
        return None

lat_env = os.environ.get("WEATHER_LAT")
lon_env = os.environ.get("WEATHER_LON")

if lat_env and lon_env:
    lat, lon, city = float(lat_env), float(lon_env), os.environ.get("WEATHER_CITY", "")
else:
    headers = {"User-Agent": "quickshell-weather/1.0"}
    loc = fetch("https://ipapi.co/json/", headers)
    if loc and loc.get("latitude"):
        lat, lon, city = loc["latitude"], loc["longitude"], loc.get("city", "")
    else:
        loc = fetch("http://ip-api.com/json/")
        if loc and loc.get("status") == "success":
            lat, lon, city = loc["lat"], loc["lon"], loc.get("city", "")
        else:
            print(json.dumps({"temp": 0, "code": -1, "city": ""}))
            sys.exit(0)

if not lat or not lon:
    print(json.dumps({"temp": 0, "code": -1, "city": city or ""}))
    sys.exit(0)

data = fetch(f"https://api.open-meteo.com/v1/forecast?latitude={lat}&longitude={lon}&current_weather=true")
if not data:
    print(json.dumps({"temp": 0, "code": -1, "city": city or ""}))
    sys.exit(0)

cw = data.get("current_weather", {})
print(json.dumps({
    "temp": cw.get("temperature", 0),
    "code": cw.get("weathercode", 0),
    "city": city or ""
}))
