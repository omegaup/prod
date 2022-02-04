#!/usr/bin/python3
"""Samples submissions for 1000 rows per language,verdict combination.

This needs that the following command is run:

    mysql -B -e '\
        SELECT \
            s.submission_id, s.guid, p.alias, s.language, \
            s.verdict, r.score, r.version, r.commit \
        FROM Submissions s \
        INNER JOIN Problems p ON p.problem_id = s.problem_id \
        INNER JOIN Runs r ON r.run_id = s.current_run_id \
        WHERE s.status = "ready";\
    ' omegaup > submissions.raw.csv
"""

import argparse
import os
import os.path
import sqlite3

import pandas as pd


def _main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--database', default='submissions.db')
    parser.add_argument('--csv', default='submissions.raw.csv')
    parser.add_argument('--sample-size', default=1000, type=int)
    args = parser.parse_args()

    if os.path.isfile(args.database):
        os.unlink(args.database)
    con = sqlite3.connect(args.database)
    with con:
        con.execute('''
            CREATE TABLE Submissions (
                submission_id INT PRIMARY KEY NOT NULL,
                guid VARCHAR NOT NULL,
                problem VARCHAR NOT NULL,
                language VARCHAR NOT NULL,
                `commit` VARCHAR NOT NULL,
                version VARCHAR NOT NULL,
                old_state VARCHAR NOT NULL,
                old_verdict VARCHAR NOT NULL,
                old_score REAL NOT NULL,
                old_runtime REAL NOT NULL,
                old_memory REAL NOT NULL,
                old_syscalls VARCHAR NULL DEFAULT NULL,
                new_state VARCHAR NOT NULL,
                new_verdict VARCHAR NOT NULL,
                new_score REAL NOT NULL,
                new_runtime REAL NOT NULL,
                new_memory REAL NOT NULL,
                new_syscalls VARCHAR NULL DEFAULT NULL
            );
        ''')

    df = pd.read_csv(args.csv, sep='\t')

    sampled = df.groupby(['language', 'verdict']).apply(
        lambda x: x.sample(n=args.sample_size, replace=True)).drop_duplicates()
    with con:
        con.executemany(
            '''INSERT INTO Submissions VALUES (
                :submission_id,
                :guid,
                :alias,
                :language,
                :commit,
                :version,
                'new',
                'JE',
                0.0,
                0.0,
                0.0,
                NULL,
                'new',
                'JE',
                0.0,
                0.0,
                0.0,
                NULL
            );''',
            [row._asdict() for row in sampled.itertuples(index=False)],
        )
    con.close()


if __name__ == '__main__':
    _main()
