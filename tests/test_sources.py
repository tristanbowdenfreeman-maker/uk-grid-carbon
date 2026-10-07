from datetime import date

from grid_carbon.sources import FIRST_DAY, TARIFF_REGIONS, Downloader, Window, all_windows


def test_windows_cover_every_day_without_gaps():
    windows = all_windows(date(2026, 10, 4))
    for source, days in [("national", 14), ("generation", 14), ("regional", 7)]:
        mine = [w for w in windows if w.source == source]
        assert mine[0].start == FIRST_DAY
        assert all((w.end - w.start).days == days for w in mine)
        assert all(a.end == b.start for a, b in zip(mine, mine[1:]))
        assert mine[-1].start <= date(2026, 10, 4) < mine[-1].end


def test_weather_windows_are_calendar_months():
    weather = [w for w in all_windows(date(2026, 10, 4)) if w.source == "weather"]
    assert weather[0].start == date(2018, 5, 1)
    assert weather[-1].start == date(2026, 10, 1) and weather[-1].end == date(2026, 11, 1)
    assert all(w.start.day == 1 and w.end.day == 1 for w in weather)


def test_neso_mix_windows_are_calendar_months_from_2009():
    mix = [w for w in all_windows(date(2026, 10, 4)) if w.source == "neso_mix"]
    assert mix[0].start == date(2009, 1, 1)
    assert mix[-1].start == date(2026, 10, 1) and mix[-1].end == date(2026, 11, 1)
    assert all(a.end == b.start for a, b in zip(mix, mix[1:]))
    assert len(mix) == 18 * 12 - 2


def test_capacity_is_one_window():
    assert [w.source for w in all_windows(date(2026, 10, 4))].count("capacity") == 1


def test_price_windows_split_where_the_agile_version_changes():
    """A month that spans a product launch is fetched from both versions, each for its own days,
    and every region's paged results are joined up."""
    import json

    class FakeResponse:
        def __init__(self, body):
            self.body = body

        def json(self):
            return self.body

    class Fake(Downloader):
        def __init__(self):
            super().__init__(pause=0)
            self.calls = []

        def agile_products(self):
            return [(date(2024, 4, 3), "OLD"), (date(2024, 10, 1), "NEW")]

        def get(self, url, params=None):
            self.calls.append((url, params))
            if url.endswith("page2"):
                return FakeResponse({"results": [{"valid_from": "b", "value_inc_vat": 2.0}], "next": None})
            return FakeResponse({"results": [{"valid_from": "a", "value_inc_vat": 1.0}], "next": url + "page2"})

    fake = Fake()
    payload = json.loads(fake._download_prices(Window("prices", date(2024, 9, 1), date(2024, 11, 1))))
    assert [(p["product"], p["from"], p["to"]) for p in payload["parts"]] == [
        ("OLD", "2024-09-01", "2024-10-01"), ("NEW", "2024-10-01", "2024-11-01")]
    assert set(payload["parts"][0]["regions"]) == set(TARIFF_REGIONS)
    assert payload["parts"][0]["regions"]["A"] == [{"from": "a", "p": 1.0}, {"from": "b", "p": 2.0}]
    first = fake.calls[0]
    assert first[1]["period_from"] == "2024-09-01T00:00Z" and first[1]["period_to"] == "2024-10-01T00:00Z"
