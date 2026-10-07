from grid_carbon.db import split_batches, sql_files


def test_split_batches_on_go_lines_only():
    script = "CREATE TABLE a (go_live INT);\nGO\nSELECT 1\n  go  \nSELECT 2"
    assert split_batches(script) == ["CREATE TABLE a (go_live INT);", "SELECT 1", "SELECT 2"]


def test_sql_files_run_folder_by_folder():
    names = [f"{p.parent.name}/{p.name}" for p in sql_files()]
    assert names[0] == "0_setup/01_schemas.sql"
    assert names == sorted(names)
    assert names[-1].startswith("5_checks/")
