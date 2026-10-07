"""Azure Function: once a day, download what's new, load it, check it and publish the site data.

The same steps as `python -m grid_carbon run`, on a timer. Settings come from the Function App's
application settings (infra/deploy.sh sets them). Runs at 05:30 UTC. Once a day keeps the database inside its free
allowance: it stays awake for an hour after each run, and the free offer won't shorten that.
"""

import logging

import azure.functions as func

from grid_carbon import pipeline
from grid_carbon.config import load_settings
from grid_carbon.db import connect
from grid_carbon.export import export
from grid_carbon.transform import failed_checks, transform

app = func.FunctionApp()


@app.timer_trigger(schedule="0 30 5 * * *", arg_name="timer", run_on_startup=False)
def refresh(timer: func.TimerRequest) -> None:
    settings = load_settings()
    with connect(settings) as conn:
        windows = pipeline.fetch(conn)
        logging.info("Downloaded %s windows", windows)
        transform(conn)
        failures = failed_checks(conn)
    for name, blocking, count in failures:
        logging.warning("%s check: %s: %s", "Blocking" if blocking else "Non-blocking", name, count)
    if any(blocking for _, blocking, _ in failures):
        raise RuntimeError("Blocking data checks failed: the site keeps its last good data")
    export(settings, local=False)
    logging.info("Site data published")
