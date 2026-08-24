"""Copy the production SQLite data into an empty PostgreSQL database.

The target URL is read from TARGET_DATABASE_URL so passwords never need to
appear in command-line arguments. The migration is all-or-nothing and refuses
to write into a database that already contains application rows.
"""

import os
import sys
from pathlib import Path

from sqlalchemy import MetaData, Table, create_engine, func, select, text

from app.database import Base
from app import models  # noqa: F401 - registers all model tables in metadata


TABLES = ("employees", "checkins", "face_profiles", "location_pings")


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: migrate_sqlite_to_postgres.py PATH_TO_SQLITE_DB")
        return 2

    sqlite_path = Path(sys.argv[1]).resolve()
    target_url = os.environ.get("TARGET_DATABASE_URL", "").strip()
    if not sqlite_path.is_file():
        raise SystemExit(f"SQLite file not found: {sqlite_path}")
    if not target_url.startswith(("postgresql://", "postgresql+psycopg2://")):
        raise SystemExit("TARGET_DATABASE_URL must be a PostgreSQL URL")

    source = create_engine(f"sqlite:///{sqlite_path.as_posix()}")
    target = create_engine(target_url, pool_pre_ping=True)
    source_metadata = MetaData()

    Base.metadata.create_all(target)

    copied: dict[str, int] = {}
    with source.connect() as source_conn, target.begin() as target_conn:
        existing = {
            name: target_conn.scalar(select(func.count()).select_from(Base.metadata.tables[name]))
            for name in TABLES
        }
        if any(existing.values()):
            raise RuntimeError(f"Target database is not empty: {existing}")

        for name in TABLES:
            source_table = Table(name, source_metadata, autoload_with=source)
            target_table = Base.metadata.tables[name]
            rows = [dict(row) for row in source_conn.execute(select(source_table)).mappings()]
            if rows:
                target_conn.execute(target_table.insert(), rows)
            copied[name] = len(rows)

        for name in TABLES:
            target_conn.execute(
                text(
                    "SELECT setval(pg_get_serial_sequence(:table_name, 'id'), "
                    "COALESCE(MAX(id), 1), MAX(id) IS NOT NULL) FROM " + name
                ),
                {"table_name": name},
            )

        verified = {
            name: target_conn.scalar(select(func.count()).select_from(Base.metadata.tables[name]))
            for name in TABLES
        }
        if copied != verified:
            raise RuntimeError(f"Row-count verification failed: source={copied}, target={verified}")

    print(f"Migration verified: {copied}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
