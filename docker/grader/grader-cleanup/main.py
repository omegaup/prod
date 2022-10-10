#!/usr/bin/python3
"""Script to delete old grader resources."""

import datetime
import itertools
import logging
import os
import os.path
import shutil
import time

from typing import Iterable, Tuple


def _walk(
    root: str,
    depth: int,
    file: bool,
    min_age_days: int,
) -> Iterable[Tuple[str, int]]:
    now = time.time()
    root = os.path.realpath(root)
    for dirname, dirs, files in os.walk(root):
        rel = os.path.relpath(dirname, root)
        current_depth = 0
        if rel != '.':
            current_depth = 1 + sum(1 for c in rel if c == '/')
        if current_depth < depth:
            continue
        for name in (files if file else dirs):
            path = os.path.join(dirname, name)
            stat = os.stat(path)
            ctime = min(stat.st_mtime, stat.st_ctime)
            age_in_days = int(now - ctime) // 3600 // 24
            if age_in_days >= min_age_days:
                yield (path, ctime)
        # Prevent recursion.
        dirs.clear()


def _main() -> None:
    logging.basicConfig(level=logging.INFO)

    logging.info('starting...')
    for path, ctime in itertools.chain(
            _walk(
                '/var/lib/omegaup/ephemeral',
                depth=0,
                file=False,
                min_age_days=1,
            ),
            _walk(
                '/var/lib/omegaup/grade',
                depth=2,
                file=False,
                min_age_days=128,
            ),
    ):
        logging.info(
            '%s %s', path,
            datetime.datetime.utcfromtimestamp(ctime).strftime(
                '%Y-%m-%dT%H:%M:%SZ'))
        shutil.rmtree(path)

    for path, ctime in _walk(
            '/var/lib/omegaup/submissions',
            depth=1,
            file=True,
            min_age_days=128,
    ):
        logging.info(
            '%s %s', path,
            datetime.datetime.utcfromtimestamp(ctime).strftime(
                '%Y-%m-%dT%H:%M:%SZ'))
        os.remove(path)
    logging.info('done')


if __name__ == '__main__':
    _main()
