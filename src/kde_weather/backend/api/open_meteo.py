"""
HTTP client for the Open-Meteo API.

Open-Meteo is a free weather API that requires no API key.  It serves
WMO weather data (the same source as the US NWS) with customizable units
and timezone handling.

We request all available hourly parameters upfront rather than filtering
by enabled_elements because:
  1. The API response is small (~15 KB) either way
  2. It avoids re-fetching when the user toggles an element on
  3. The hourly data is also used to populate current conditions (index 0)
"""

import requests

FORECAST_URL = "https://api.open-meteo.com/v1/forecast"
GEOCODE_URL = "https://geocoding-api.open-meteo.com/v1/search"

# Every hourly field we might display as a chart.
# These names are the Open-Meteo API parameter names.
HOURLY_PARAMS = [
    "temperature_2m",
    "apparent_temperature",
    "relative_humidity_2m",
    "precipitation_probability",
    "rain",
    "snowfall",
    "snow_depth",
    "cloud_cover",
    "wind_speed_10m",
    "wind_gusts_10m",
    "wind_direction_10m",
    "weather_code",       # WMO code for icon selection
]

# Daily summary fields for the 7-day forecast cards.
DAILY_PARAMS = [
    "temperature_2m_max",
    "temperature_2m_min",
    "apparent_temperature_max",
    "apparent_temperature_min",
    "precipitation_probability_max",
    "precipitation_sum",
    "rain_sum",
    "snowfall_sum",
    "wind_speed_10m_max",
    "wind_gusts_10m_max",
    "weather_code",
    "sunrise",
    "sunset",
]


def fetch_forecast(lat: float, lon: float) -> dict:
    """Fetch a 7-day forecast with hourly + daily data.

    Returns the raw JSON dict from Open-Meteo.  Units are set to US
    customary (°F, mph, inches) since this app targets US users.
    The "timezone=auto" parameter tells Open-Meteo to return times in the
    location's local timezone rather than UTC.
    """
    resp = requests.get(
        FORECAST_URL,
        params={
            "latitude": lat,
            "longitude": lon,
            "hourly": ",".join(HOURLY_PARAMS),
            "daily": ",".join(DAILY_PARAMS),
            "temperature_unit": "fahrenheit",
            "wind_speed_unit": "mph",
            "precipitation_unit": "inch",
            "timezone": "auto",
            "forecast_days": 7,
        },
        timeout=15,
    )
    resp.raise_for_status()
    return resp.json()


def fetch_geocode(name: str, count: int = 5) -> list[dict]:
    """Search for cities by name, returning up to `count` results.

    Results include latitude, longitude, admin1 (state/region), and
    country for display in the autocomplete dropdown.
    """
    resp = requests.get(
        GEOCODE_URL,
        params={
            "name": name,
            "count": count,
            "language": "en",
            "format": "json",
        },
        timeout=10,
    )
    resp.raise_for_status()
    data = resp.json()
    return data.get("results", [])
