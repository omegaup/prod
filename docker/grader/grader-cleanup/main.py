#!/usr/bin/python3
"""Script to delete old grader resources."""

import datetime
import itertools
import logging
import os
import os.path
import time

from typing import Iterable, Tuple


def _walk(
    root: str,
    depth: int,
    file: bool,
    min_age_days: int,
) -> Iterable[Tuple[str, int]]:
    now = time.time()
    for dirname, dirs, files in os.walk(root):
        rel = os.path.relpath(dirname, root)
        current_depth = 0
        if rel != '.':
            current_depth = 1 + sum(1 for c in rel if c == '/')
        if current_depth == depth:
            for name in (files if file else dirs):
                path = os.path.join(dirname, name)
                stat = os.stat(path)
                age_in_days = int(now - stat.st_ctime) // 3600 // 24
                if age_in_days >= min_age_days:
                    yield (path, stat.st_ctime)
            # Prevent recursion.
            dirs.clear()


def _main() -> None:
    logging.basicConfig(level=logging.INFO)

    logging.info('starting...')
    for path, ctime in itertools.chain(
            _walk(
                '/var/lib/omegaup/ephemeral',
                depth=1,
                file=False,
                min_age_days=1,
            ),
            _walk(
                '/var/lib/omegaup/grade',
                depth=3,
                file=False,
                min_age_days=128,
            ),
            _walk(
                '/var/lib/omegaup/submissions',
                depth=1,
                file=True,
                min_age_days=128,
            ),
    ):
        logging.info(
            '%s %s', path,
            datetime.datetime.utcfromtimestamp(ctime).strftime(
                '%Y-%m-%dT%H:%M:%SZ'))
    logging.info('done')
    time.sleep(999999)


if __name__ == '__main__':
    _main()
