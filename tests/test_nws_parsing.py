#!/usr/bin/env python
"""Tests for the NWS client and its pure parsing helpers.

No framework; run directly:
    PYTHONPATH=src python tests/test_nws_parsing.py
Each test_* function raises AssertionError on failure; the runner reports
results and exits non-zero if any fail.
"""
import os
import sys

sys.path.insert(0, os.path.normpath(os.path.join(os.path.dirname(__file__), "..", "src")))

from kde_weather.backend.api import nws


def test_periods_for_date_selects_day_and_night():
    periods = [
        {"name": "Wednesday", "isDaytime": True,
         "startTime": "2026-06-17T06:00:00-04:00", "detailedForecast": "Sunny."},
        {"name": "Wednesday Night", "isDaytime": False,
         "startTime": "2026-06-17T18:00:00-04:00", "detailedForecast": "Clear."},
        {"name": "Thursday", "isDaytime": True,
         "startTime": "2026-06-18T06:00:00-04:00", "detailedForecast": "Cloudy."},
    ]
    res = nws.periods_for_date(periods, "2026-06-17")
    assert res["day"]["name"] == "Wednesday", res
    assert res["night"]["name"] == "Wednesday Night", res


def test_periods_for_date_missing_returns_none():
    res = nws.periods_for_date([], "2026-06-17")
    assert res == {"day": None, "night": None}, res


def test_alerts_for_date_includes_overlapping():
    alerts = [{"properties": {
        "event": "Winter Storm Warning",
        "effective": "2026-06-17T12:00:00-04:00",
        "expires": "2026-06-18T06:00:00-04:00"}}]
    res = nws.alerts_for_date(alerts, "2026-06-17")
    assert len(res) == 1 and res[0]["event"] == "Winter Storm Warning", res


def test_alerts_for_date_excludes_outside_window():
    alerts = [{"properties": {
        "event": "Heat Advisory",
        "effective": "2026-06-20T12:00:00-04:00",
        "expires": "2026-06-21T06:00:00-04:00"}}]
    res = nws.alerts_for_date(alerts, "2026-06-17")
    assert res == [], res


def test_alerts_for_date_accepts_unwrapped_props_and_onset_fallback():
    # Unwrapped property dict (no 'properties' wrapper) using onset/ends fallback.
    alerts = [{
        "event": "Flood Watch",
        "onset": "2026-06-17T08:00:00-04:00",
        "ends": "2026-06-17T20:00:00-04:00"}]
    res = nws.alerts_for_date(alerts, "2026-06-17")
    assert len(res) == 1 and res[0]["event"] == "Flood Watch", res


def test_alerts_for_date_includes_fully_encompassing_alert():
    # Alert starts before the day and ends after it -> active all day.
    alerts = [{"properties": {
        "event": "Coastal Flood Warning",
        "effective": "2026-06-16T00:00:00-04:00",
        "expires": "2026-06-19T00:00:00-04:00"}}]
    res = nws.alerts_for_date(alerts, "2026-06-17")
    assert len(res) == 1 and res[0]["event"] == "Coastal Flood Warning", res


def test_format_expires_human_readable():
    assert nws.format_expires("2026-06-18T18:00:00-04:00") == "until Thu 6:00 PM", \
        nws.format_expires("2026-06-18T18:00:00-04:00")
    assert nws.format_expires("") == ""
    assert nws.format_expires("garbage") == ""


class _FakeResp:
    def __init__(self, status=200, payload=None):
        self.status_code = status
        self._payload = payload or {}

    def raise_for_status(self):
        if self.status_code >= 400:
            raise AssertionError(f"raise_for_status called on {self.status_code}")

    def json(self):
        return self._payload


def _install_fake_get(mapping):
    """Replace nws.requests.get with a URL-dispatching fake; return a restore fn.

    `mapping` maps a substring of the URL to a _FakeResp.
    """
    orig = nws.requests.get

    def fake_get(url, *args, **kwargs):
        for needle, resp in mapping.items():
            if needle in url:
                return resp
        raise AssertionError(f"unexpected URL {url!r}")

    nws.requests.get = fake_get
    return lambda: setattr(nws.requests, "get", orig)


def test_fetch_unavailable_when_point_404():
    restore = _install_fake_get({"/points/": _FakeResp(status=404)})
    try:
        res = nws.fetch_nws_details(0.0, 0.0)
    finally:
        restore()
    assert res == {"available": False, "periods": [], "alerts": []}, res


def test_fetch_happy_path_returns_periods_and_alerts():
    mapping = {
        "/points/": _FakeResp(payload={
            "properties": {"forecast": "https://api.weather.gov/gridpoints/X/1,1/forecast"}}),
        "/forecast": _FakeResp(payload={
            "properties": {"periods": [{"name": "Today", "isDaytime": True}]}}),
        "/alerts/active": _FakeResp(payload={
            "features": [{"properties": {"event": "Test Warning"}}]}),
    }
    restore = _install_fake_get(mapping)
    try:
        res = nws.fetch_nws_details(43.0, -76.0)
    finally:
        restore()
    assert res["available"] is True, res
    assert res["periods"][0]["name"] == "Today", res
    assert res["alerts"][0]["properties"]["event"] == "Test Warning", res


def _run():
    tests = [v for k, v in sorted(globals().items())
             if k.startswith("test_") and callable(v)]
    failed = 0
    for t in tests:
        try:
            t()
            print(f"[PASS] {t.__name__}")
        except AssertionError as e:
            failed += 1
            print(f"[FAIL] {t.__name__}: {e}")
    if failed:
        print(f"\n{failed} of {len(tests)} failed")
        sys.exit(1)
    print(f"\nAll {len(tests)} passed")


if __name__ == "__main__":
    _run()
