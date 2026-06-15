"""HTTP client + parsing for the US National Weather Service (NWS/NOAA) API.

What: api.weather.gov provides narrative forecasts and active alerts.
Why:  Open-Meteo (the app's primary source) has neither narrative text nor US
      alerts, so this is a second, US-only source used by the 7-Day tab.
How:  fetch_nws_details() (Task 2) does the network flow; the period/alert
      parsing lives in pure helpers here so it can be unit-tested offline.

NWS requires a descriptive User-Agent header or it returns 403.
"""
from datetime import datetime, timedelta

import requests

# NWS asks for a User-Agent identifying the app (and ideally a contact).
# See https://www.weather.gov/documentation/services-web-api
NWS_USER_AGENT = "kde-weather (github.com/npatricksmith-oss/kde-weather)"
_HEADERS = {"User-Agent": NWS_USER_AGENT, "Accept": "application/geo+json"}

POINTS_URL = "https://api.weather.gov/points/{lat},{lon}"
ALERTS_URL = "https://api.weather.gov/alerts/active"


def _parse_iso(ts):
    """Parse an NWS ISO-8601 timestamp like '2026-06-12T18:00:00-04:00'.

    What: Converts an ISO-8601 string to a timezone-aware datetime.
    Why:  NWS uses offset-aware timestamps; centralising parsing avoids
          repeated try/except blocks and keeps callers clean.
    Returns a timezone-aware datetime, or None when ts is falsy/unparseable.
    datetime.fromisoformat handles the trailing offset on Python 3.11+.
    """
    if not ts:
        return None
    try:
        return datetime.fromisoformat(ts)
    except (ValueError, TypeError):
        return None


def periods_for_date(periods, date_str):
    """Return {'day': period|None, 'night': period|None} for a YYYY-MM-DD date.

    What: Filters the NWS forecast periods list to the two periods (day and
          night) that start on the given date.
    Why:  NWS returns ~14 periods (7 days × 2); the caller needs only the pair
          for one specific date to populate the day-detail view.
    How:  Compares the local date portion of each period's startTime to
          date_str. isDaytime True → 'day' slot; False → 'night' slot.
          If more than one of a kind matches (shouldn't happen), the first wins.
    """
    result = {"day": None, "night": None}
    for p in periods:
        # Parse the period's start time; skip if missing or unparseable
        start = _parse_iso(p.get("startTime"))
        if start is None or start.strftime("%Y-%m-%d") != date_str:
            continue
        # Map isDaytime boolean to the dict slot name
        slot = "day" if p.get("isDaytime") else "night"
        if result[slot] is None:
            result[slot] = p
    return result


def alerts_for_date(alerts, date_str):
    """Return alert *properties* whose active window overlaps the local day.

    What: Filters a list of raw NWS GeoJSON alert features to only those
          that are active at any point during the specified calendar day.
    Why:  A day-detail view should surface any alert that could affect the user
          during that day, even if the alert spans midnight boundaries.
    How:  Accepts either raw GeoJSON features ({'properties': {...}}) or
          already-unwrapped property dicts. The day window is
          [date 00:00, date+1 00:00). The alert window is
          [effective|onset, expires|ends]; a missing start means "already
          active", a missing end means "open-ended". Times are compared on
          wall-clock (tzinfo dropped), which matches how NWS issues alerts in
          local time.
    """
    # Build the half-open interval [day_start, day_end) for the target date
    day_start = datetime.fromisoformat(date_str + "T00:00:00")
    day_end = day_start + timedelta(days=1)
    out = []
    for a in alerts:
        # Support both raw GeoJSON features and already-unwrapped property dicts
        props = a.get("properties", a)
        # Use effective/onset for start, expires/ends for end
        start = _parse_iso(props.get("effective") or props.get("onset"))
        end = _parse_iso(props.get("expires") or props.get("ends"))
        # Strip tzinfo to compare wall-clock times (NWS uses local time)
        s = start.replace(tzinfo=None) if start else None
        e = end.replace(tzinfo=None) if end else None
        # Skip if alert ended before the day started
        if e is not None and e < day_start:
            continue
        # Skip if alert starts after the day ended
        if s is not None and s >= day_end:
            continue
        out.append(props)
    return out


def format_expires(ts):
    """Human-friendly end time, e.g. 'until Thu 6:00 PM'. '' if unparseable.

    What: Converts an ISO-8601 expiry timestamp to a short human label.
    Why:  Alert UI shows 'until Thu 6:00 PM' rather than a raw ISO string,
          so the user immediately knows when the alert lapses.
    """
    dt = _parse_iso(ts)
    if dt is None:
        return ""
    # %-I uses the non-zero-padded hour (e.g. '6' not '06') on Linux
    return dt.strftime("until %a %-I:%M %p")


def fetch_nws_details(lat, lon):
    """Fetch NWS day/night periods + active alerts for a point.

    What: Makes up to three requests — /points, the forecast URL it returns,
          and /alerts/active — and returns the combined result.
    Why:  NWS is US-only; the points endpoint returns 404 for non-US
          coordinates, so we use that as the availability signal rather than
          raising an exception (the caller doesn't need to treat this as an
          error).
    How:  Any 404 on the points call → available=False (outside NWS coverage).
          Any other HTTP/network failure raises so NwsWorker can surface it as
          an error state. The three requests all send the required User-Agent.
    Returns {"available": bool, "periods": list, "alerts": list}.
    """
    points = requests.get(
        POINTS_URL.format(lat=lat, lon=lon), headers=_HEADERS, timeout=15
    )
    if points.status_code == 404:
        # Outside NWS coverage (non-US location); not an error, just unavailable
        return {"available": False, "periods": [], "alerts": []}
    points.raise_for_status()
    forecast_url = points.json().get("properties", {}).get("forecast")
    if not forecast_url:
        # Points endpoint succeeded but returned no forecast URL; treat as unavailable
        return {"available": False, "periods": [], "alerts": []}

    forecast = requests.get(forecast_url, headers=_HEADERS, timeout=15)
    forecast.raise_for_status()
    periods = forecast.json().get("properties", {}).get("periods", [])

    alerts_resp = requests.get(
        ALERTS_URL,
        headers=_HEADERS,
        params={"point": f"{lat},{lon}", "status": "actual"},
        timeout=15,
    )
    alerts_resp.raise_for_status()
    alerts = alerts_resp.json().get("features", [])

    return {"available": True, "periods": periods, "alerts": alerts}
