#!/usr/bin/python3
"""Upload the grader queue length to Azure as metrics for the autoscaler."""

import argparse
import datetime
import logging
import os
import time

from typing import Any, Dict, Mapping

from opencensus.ext.azure import metrics_exporter  # type: ignore
from opencensus.metrics.export import gauge  # type: ignore
from prometheus_client import parser  # type: ignore
from pythonjsonlogger import jsonlogger  # type: ignore
import requests

_UTC = datetime.timezone.utc
_SAMPLE_INTERVAL = datetime.timedelta(seconds=15)


class _CustomJsonFormatter(jsonlogger.JsonFormatter):  # type: ignore
    """A JSON formatter that adds the level."""
    def add_fields(
        self,
        log_record: Dict[str, str],
        record: logging.LogRecord,
        message_dict: Mapping[str, Any],
    ) -> None:
        super().add_fields(log_record, record, message_dict)
        if not log_record.get('time'):
            log_record['time'] = datetime.datetime.utcnow().strftime(
                '%Y-%m-%dT%H:%M:%S.%fZ')
        if log_record.get('level'):
            log_record['level'] = log_record['level'].lower()
        else:
            log_record['level'] = record.levelname.lower()


def _queue_length(grader_prometheus: str) -> float:
    """Gets the grader queue length from the grader's Prometheus."""
    req = requests.get(grader_prometheus, timeout=(3, 9))
    for metric_family in parser.text_string_to_metric_families(req.text):
        if metric_family.name != 'quark_grader_queue_total_length':
            continue
        for sample in metric_family.samples:
            return float(sample.value)
    return 0.0


def _main() -> None:
    argparser = argparse.ArgumentParser()
    argparser.add_argument('--grader-prometheus',
                           default='http://grader.omegaup.com:6061/metrics')
    default_connection_string = os.getenv('CONNECTION_STRING')
    argparser.add_argument('--connection-string',
                           default=default_connection_string,
                           type=str,
                           required=default_connection_string is None)
    args = argparser.parse_args()

    log_handler = logging.StreamHandler()
    formatter = _CustomJsonFormatter()
    log_handler.setFormatter(formatter)
    logging.basicConfig(level=logging.INFO, handlers=[log_handler], force=True)
    logging.info('Starting grader_metrics.py')

    now = int(time.time())
    target_time = datetime.datetime.fromtimestamp(now, tz=_UTC)
    target_time = target_time.replace(second=0, microsecond=0)
    tick_time = datetime.datetime.fromtimestamp(now, _UTC)
    tick_time = tick_time.replace(
        second=tick_time.second -
        tick_time.second % int(_SAMPLE_INTERVAL.total_seconds()),
        microsecond=0)
    data = []

    exporter = metrics_exporter.new_metrics_exporter(
        enable_standard_metrics=False,
        connection_string=args.connection_string)

    queue_length_gauge = gauge.DoubleGauge(
        (r'\ASP.NET Applications(??APP_W3SVC_PROC??)'
         r'\Requests In Application Queue'),
        'HTTP Requests in application queue',
        'requests',
        [],
    )
    queue_length_ts = queue_length_gauge.get_or_create_time_series(())

    while True:
        try:
            data.append(_queue_length(args.grader_prometheus))
            logging.info('tick: %s %s', tick_time, data)
            if datetime.datetime.now(tz=_UTC) >= target_time:
                queue_length_ts.set(max(data))
                exporter.export_metrics(
                    (queue_length_gauge.get_metric(target_time), ))
                data = []
                target_time += datetime.timedelta(minutes=1)
        except Exception:  # pylint: disable=broad-except
            logging.exception('Round failed')

        tick_time += _SAMPLE_INTERVAL
        time.sleep(
            max(0,
                (tick_time - datetime.datetime.now(tz=_UTC)).total_seconds()))


if __name__ == '__main__':
    _main()
