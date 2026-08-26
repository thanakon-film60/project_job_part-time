from sqlalchemy import create_engine, inspect, text
from sqlalchemy.orm import declarative_base, sessionmaker

from .config import settings

engine = create_engine(settings.database_url, pool_pre_ping=True)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()


# คอลัมน์ที่เพิ่มทีหลัง: (ตาราง, ชื่อคอลัมน์, ชนิด SQL)
# create_all() สร้างได้เฉพาะ "ตารางใหม่" ไม่เติมคอลัมน์ให้ตารางที่มีอยู่แล้ว
# จึงต้องเติมเองตอนสตาร์ต ไม่งั้นฐานข้อมูลเดิมจะพังเวลา query คอลัมน์ใหม่
_ADDED_COLUMNS = [
    ("checkins", "office_name", "VARCHAR(120)"),
    ("location_pings", "office_name", "VARCHAR(120)"),
    ("face_profiles", "sort_order", "INTEGER"),
    ("employees", "birth_date", "DATE"),
    ("employees", "national_id_encrypted", "VARCHAR(255)"),
    ("employees", "national_id_hash", "VARCHAR(64)"),
    ("employees", "phone", "VARCHAR(20)"),
    ("employees", "address_line", "VARCHAR(255)"),
    ("employees", "postal_code", "VARCHAR(5)"),
    ("employees", "subdistrict", "VARCHAR(120)"),
    ("employees", "district", "VARCHAR(120)"),
    ("employees", "province", "VARCHAR(120)"),
    ("employees", "department", "VARCHAR(120)"),
    ("employees", "position", "VARCHAR(120)"),
    ("employees", "start_date", "DATE"),
    ("employees", "updated_at", "TIMESTAMP"),
]


def apply_pending_migrations() -> list[str]:
    """เติมคอลัมน์ที่ยังไม่มีให้ฐานข้อมูลเดิม (ทำซ้ำได้ ไม่พังถ้ามีอยู่แล้ว)"""
    applied = []
    inspector = inspect(engine)
    existing_tables = set(inspector.get_table_names())

    with engine.begin() as conn:
        for table, column, sql_type in _ADDED_COLUMNS:
            if table not in existing_tables:
                continue  # create_all() จะสร้างให้พร้อมคอลัมน์ครบอยู่แล้ว
            cols = {c["name"] for c in inspector.get_columns(table)}
            if column in cols:
                continue
            conn.execute(text(f"ALTER TABLE {table} ADD COLUMN {column} {sql_type}"))
            applied.append(f"{table}.{column}")
    return applied


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
