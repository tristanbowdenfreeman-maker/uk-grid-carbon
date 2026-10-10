import pymssql
import pytest

from grid_carbon import db
from grid_carbon.db import split_batches, sql_files


def test_split_batches_on_go_lines_only():
    script = "CREATE TABLE a (go_live INT);\nGO\nSELECT 1\n  go  \nSELECT 2"
    assert split_batches(script) == ["CREATE TABLE a (go_live INT);", "SELECT 1", "SELECT 2"]


def test_sql_files_run_folder_by_folder():
    names = [f"{p.parent.name}/{p.name}" for p in sql_files()]
    assert names[0] == "0_setup/01_schemas.sql"
    assert names == sorted(names)
    assert names[-1].startswith("5_checks/")


def _settings():
    return db.Settings(**{name: None for name in db.Settings.__dataclass_fields__})


def test_connect_waits_for_a_paused_database(monkeypatch):
    attempts = []

    def fake_connect(**kwargs):
        attempts.append(1)
        if len(attempts) < 3:
            raise pymssql.OperationalError((40613, b"Database is not currently available."))
        return "connection"

    monkeypatch.setattr(db.pymssql, "connect", fake_connect)
    monkeypatch.setattr(db.time, "sleep", lambda seconds: None)
    assert db.connect(_settings()) == "connection"
    assert len(attempts) == 3


def test_connect_gives_up_on_other_errors(monkeypatch):
    def fake_connect(**kwargs):
        raise pymssql.OperationalError((18456, b"Login failed."))

    monkeypatch.setattr(db.pymssql, "connect", fake_connect)
    with pytest.raises(pymssql.OperationalError):
        db.connect(_settings())
