#!/usr/bin/env python3
"""
Local Mock API Server for Food City POS System
Upgraded to support advanced product pricing + inventory sync.
Run: python local_server.py
Endpoint: http://localhost:8080/api/pos_sync.php
"""

import json
import os
import shutil
import sqlite3
from datetime import datetime, timedelta
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs, urlparse

PROJECT_ROOT = os.path.dirname(os.path.abspath(__file__))
DB_PATH = os.path.join(PROJECT_ROOT, "local_admin.db")
LEGACY_POS_DB_PATH = os.path.join(
    PROJECT_ROOT,
    "apps",
    "pos_app",
    ".dart_tool",
    "sqflite_common_ffi",
    "databases",
    "food_city_pos.db",
)


def _resolve_stable_pos_db_path():
    local_appdata = (
        os.environ.get("LOCALAPPDATA")
        or os.environ.get("APPDATA")
        or os.path.join(os.path.expanduser("~"), "food_city_pos_data")
    )
    return os.path.join(local_appdata, "Food City POS", "data", "food_city_pos.db")


STABLE_POS_DB_PATH = _resolve_stable_pos_db_path()


def _copy_pos_sidecar_if_exists(source_path, target_path):
    if not os.path.exists(source_path):
        return
    os.makedirs(os.path.dirname(target_path), exist_ok=True)
    shutil.copy2(source_path, target_path)


def _ensure_pos_db_path():
    os.makedirs(os.path.dirname(STABLE_POS_DB_PATH), exist_ok=True)

    if os.path.exists(STABLE_POS_DB_PATH):
        return STABLE_POS_DB_PATH

    if os.path.exists(LEGACY_POS_DB_PATH):
        shutil.copy2(LEGACY_POS_DB_PATH, STABLE_POS_DB_PATH)
        _copy_pos_sidecar_if_exists(f"{LEGACY_POS_DB_PATH}-wal", f"{STABLE_POS_DB_PATH}-wal")
        _copy_pos_sidecar_if_exists(f"{LEGACY_POS_DB_PATH}-shm", f"{STABLE_POS_DB_PATH}-shm")
        print(f"✅ Migrated POS DB to stable path: {STABLE_POS_DB_PATH}")
        return STABLE_POS_DB_PATH

    return STABLE_POS_DB_PATH


POS_DB_PATH = _ensure_pos_db_path()


def get_pos_db():
    os.makedirs(os.path.dirname(POS_DB_PATH), exist_ok=True)
    conn = sqlite3.connect(POS_DB_PATH, timeout=10)
    conn.row_factory = sqlite3.Row
    return conn


def get_owner_users_db():
    if os.path.exists(POS_DB_PATH):
        return get_pos_db()
    return get_db()

def _db_identity(path):
    return os.path.abspath(path)


def _get_user_db_connections(include_backend=True):
    conns = []
    seen = set()
    if os.path.exists(POS_DB_PATH):
        pos_abs = _db_identity(POS_DB_PATH)
        if pos_abs not in seen:
            conns.append(("pos", get_pos_db(), pos_abs))
            seen.add(pos_abs)
    if include_backend:
        admin_abs = _db_identity(DB_PATH)
        if admin_abs not in seen and os.path.exists(DB_PATH):
            conns.append(("admin", get_db(), admin_abs))
            seen.add(admin_abs)
    return conns


def _close_user_db_connections(conns):
    for _name, conn, _path in conns:
        try:
            conn.close()
        except Exception:
            pass


def _dedupe_user_rows(rows):
    seen = set()
    output = []
    for row in rows:
        row_id = parse_int(row.get("id"), 0)
        name = str(row.get("name") or "").strip().lower()
        pin = str(row.get("pin") or "").strip()
        key = (row_id if row_id > 0 else None, name, pin)
        if key in seen:
            continue
        seen.add(key)
        output.append(row)
    return output


def _dedupe_activity_rows(rows):
    seen = set()
    output = []
    for row in rows:
        key = (
            str(row.get("created_at") or ""),
            str(row.get("action_type") or ""),
            str(row.get("actor_name") or ""),
            str(row.get("target_user_name") or ""),
            str(row.get("description") or ""),
        )
        if key in seen:
            continue
        seen.add(key)
        output.append(row)
    return output


def get_db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def get_table_columns(cursor, table_name):
    rows = cursor.execute(f"PRAGMA table_info({table_name})").fetchall()
    return {row[1] for row in rows}


def ensure_column(cursor, table_name, column_name, column_sql):
    columns = get_table_columns(cursor, table_name)
    if column_name not in columns:
        cursor.execute(f"ALTER TABLE {table_name} ADD COLUMN {column_sql}")


def normalize_bool(value, default=False):
    if value is None:
        return default
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return value != 0
    text = str(value).strip().lower()
    if text in {"1", "true", "yes", "y", "on"}:
        return True
    if text in {"0", "false", "no", "n", "off"}:
        return False
    return default


def parse_int(value, default=0):
    try:
        return int(value)
    except Exception:
        return default


def parse_float(value, default=0.0):
    try:
        return float(value)
    except Exception:
        return default


def round_quantity(value):
    return round(parse_float(value, 0.0), 3)


def format_quantity(value):
    text = f"{round_quantity(value):.3f}".rstrip("0").rstrip(".")
    return text or "0"


def format_stock_with_unit(quantity_type, unit_label, value):
    return f"{format_quantity(value)} {normalize_unit_label(quantity_type, unit_label)}"


def normalize_quantity_type(value):
    return "weight" if str(value or "").strip().lower() == "weight" else "unit"


def normalize_unit_label(quantity_type, value):
    trimmed = str(value or "").strip()
    if trimmed:
        return trimmed
    return "kg" if normalize_quantity_type(quantity_type) == "weight" else "pcs"


def now_sql():
    return "datetime('now','localtime')"


def normalize_customer_phone(value):
    text = str(value or "").strip()
    if not text:
        return ""
    text = text.replace(" ", "").replace("-", "").replace("(", "").replace(")", "")
    if text.startswith("+94"):
        text = "0" + text[3:]
    elif text.startswith("94") and len(text) == 11:
        text = "0" + text[2:]
    return "".join(ch for ch in text if ch.isdigit())


def normalize_customer_type(value):
    normalized = str(value or "regular").strip().lower()
    if normalized in {"vip", "wholesale", "staff"}:
        return normalized
    return "regular"


def normalize_price_type(value):
    normalized = str(value or "selling").strip().lower()
    if normalized in {"wholesale", "sale"}:
        return normalized
    return "selling"


def create_customer_tables(cursor):
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS customers (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            customer_code TEXT UNIQUE,
            name TEXT NOT NULL,
            phone TEXT,
            phone_normalized TEXT,
            email TEXT,
            address TEXT,
            customer_type TEXT NOT NULL DEFAULT 'regular',
            notes TEXT,
            is_active INTEGER NOT NULL DEFAULT 1,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            created_by INTEGER,
            updated_by INTEGER
        )
        """
    )
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_customers_name ON customers(name)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_customers_phone ON customers(phone_normalized)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_customers_code ON customers(customer_code)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_customers_active ON customers(is_active)")

    ensure_column(cursor, "customers", "credit_enabled", "credit_enabled INTEGER NOT NULL DEFAULT 0")
    ensure_column(cursor, "customers", "credit_limit", "credit_limit REAL NOT NULL DEFAULT 0")
    ensure_column(cursor, "customers", "current_credit_balance", "current_credit_balance REAL NOT NULL DEFAULT 0")
    ensure_column(cursor, "customers", "credit_status", "credit_status TEXT NOT NULL DEFAULT 'normal'")
    ensure_column(cursor, "customers", "credit_note", "credit_note TEXT")
    ensure_column(cursor, "customers", "pricing_enabled", "pricing_enabled INTEGER NOT NULL DEFAULT 0")
    ensure_column(cursor, "customers", "default_price_type", "default_price_type TEXT NOT NULL DEFAULT 'selling'")
    ensure_column(cursor, "customers", "default_discount_percent", "default_discount_percent REAL NOT NULL DEFAULT 0")
    ensure_column(cursor, "customers", "pricing_note", "pricing_note TEXT")


def create_customer_product_prices_table(cursor):
    create_customer_tables(cursor)
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS customer_product_prices (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            customer_id INTEGER NOT NULL,
            barcode TEXT NOT NULL,
            product_name_snapshot TEXT NOT NULL,
            fixed_price REAL NOT NULL,
            is_active INTEGER NOT NULL DEFAULT 1,
            note TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            created_by INTEGER,
            updated_by INTEGER,
            UNIQUE(customer_id, barcode)
        )
        """
    )
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_customer_product_prices_customer ON customer_product_prices(customer_id)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_customer_product_prices_barcode ON customer_product_prices(barcode)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_customer_product_prices_active ON customer_product_prices(is_active)")


def create_sale_items_table(cursor):
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS sale_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            sale_id INTEGER NOT NULL,
            barcode TEXT NOT NULL,
            product_name TEXT NOT NULL,
            unit_price REAL NOT NULL DEFAULT 0,
            marked_price REAL NOT NULL DEFAULT 0,
            price_category_used TEXT NOT NULL DEFAULT 'selling',
            system_unit_price REAL NOT NULL DEFAULT 0,
            price_override_type TEXT NOT NULL DEFAULT 'none',
            price_override_reason TEXT NOT NULL DEFAULT '',
            price_override_original_price REAL NOT NULL DEFAULT 0,
            price_override_difference REAL NOT NULL DEFAULT 0,
            price_history_id INTEGER,
            price_override_approved_by TEXT,
            cost_price_snapshot REAL NOT NULL DEFAULT 0,
            quantity REAL NOT NULL DEFAULT 0,
            base_line_total REAL NOT NULL DEFAULT 0,
            item_discount_type TEXT NOT NULL DEFAULT 'none',
            item_discount_value REAL NOT NULL DEFAULT 0,
            explicit_item_discount_amount REAL NOT NULL DEFAULT 0,
            cart_discount_amount REAL NOT NULL DEFAULT 0,
            item_discount_amount REAL NOT NULL DEFAULT 0,
            line_total REAL NOT NULL DEFAULT 0,
            customer_pricing_applied INTEGER NOT NULL DEFAULT 0,
            customer_pricing_type TEXT NOT NULL DEFAULT 'none',
            customer_pricing_rule_id INTEGER,
            customer_pricing_original_price REAL NOT NULL DEFAULT 0,
            customer_pricing_final_price REAL NOT NULL DEFAULT 0,
            customer_pricing_discount_amount REAL NOT NULL DEFAULT 0,
            customer_pricing_note TEXT,
            created_at TEXT NOT NULL
        )
        """
    )
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_sale_items_sale ON sale_items(sale_id)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_sale_items_barcode ON sale_items(barcode)")


def ensure_customer_sales_columns(cursor):
    create_customer_tables(cursor)
    ensure_column(cursor, "sales", "customer_id", "customer_id INTEGER")
    ensure_column(cursor, "sales", "customer_name_snapshot", "customer_name_snapshot TEXT")
    ensure_column(cursor, "sales", "customer_phone_snapshot", "customer_phone_snapshot TEXT")
    ensure_column(cursor, "sales", "customer_code_snapshot", "customer_code_snapshot TEXT")
    ensure_column(cursor, "sales", "pos_sale_id", "pos_sale_id INTEGER")
    ensure_column(cursor, "sales", "is_credit_sale", "is_credit_sale INTEGER NOT NULL DEFAULT 0")
    ensure_column(cursor, "sales", "credit_status", "credit_status TEXT")
    ensure_column(cursor, "sales", "credit_ledger_id", "credit_ledger_id INTEGER")
    ensure_column(cursor, "sales", "credit_approved_by", "credit_approved_by TEXT")
    ensure_column(cursor, "sales", "credit_previous_balance", "credit_previous_balance REAL")
    ensure_column(cursor, "sales", "credit_new_balance", "credit_new_balance REAL")
    ensure_column(cursor, "sales", "credit_bill_amount", "credit_bill_amount REAL")
    ensure_column(cursor, "sales", "credit_limit_snapshot", "credit_limit_snapshot REAL")


def generate_customer_code(customer_id):
    return f"CUS-{parse_int(customer_id, 0):06d}"


def clean_optional_text(value):
    text = str(value or "").strip()
    return text if text else None


def fetch_customers(cursor, params):
    create_customer_tables(cursor)

    search = str(params.get("search", [""])[0] or params.get("query", [""])[0] or "").strip()
    active_only = normalize_bool(params.get("active_only", ["1"])[0], True)
    include_inactive = normalize_bool(params.get("include_inactive", ["0"])[0], False)
    limit = parse_int(params.get("limit", ["100"])[0], 100)
    if limit <= 0:
        limit = 100
    if limit > 500:
        limit = 500

    where = []
    args = []

    if active_only and not include_inactive:
        where.append("COALESCE(is_active, 1) = 1")

    if search:
        phone_search = normalize_customer_phone(search)
        like = f"%{search.lower()}%"
        where.append(
            """
            (
                LOWER(name) LIKE ?
                OR LOWER(COALESCE(customer_code, '')) LIKE ?
                OR LOWER(COALESCE(email, '')) LIKE ?
                OR LOWER(COALESCE(address, '')) LIKE ?
                OR COALESCE(phone, '') LIKE ?
                OR COALESCE(phone_normalized, '') LIKE ?
            )
            """
        )
        args.extend([
            like,
            like,
            like,
            like,
            f"%{search}%",
            f"%{phone_search or search}%",
        ])

    query = """
        SELECT
            id,
            customer_code,
            name,
            phone,
            phone_normalized,
            email,
            address,
            customer_type,
            notes,
            COALESCE(is_active, 1) AS is_active,
            COALESCE(pricing_enabled, 0) AS pricing_enabled,
            COALESCE(default_price_type, 'selling') AS default_price_type,
            COALESCE(default_discount_percent, 0) AS default_discount_percent,
            pricing_note,
            created_at,
            updated_at,
            created_by,
            updated_by
        FROM customers
    """
    if where:
        query += " WHERE " + " AND ".join(where)
    query += " ORDER BY COALESCE(is_active, 1) DESC, name COLLATE NOCASE ASC LIMIT ?"
    args.append(limit)

    return [dict(row) for row in cursor.execute(query, args).fetchall()]


def get_customer_by_id(cursor, customer_id):
    create_customer_tables(cursor)
    row = cursor.execute(
        """
        SELECT
            id,
            customer_code,
            name,
            phone,
            phone_normalized,
            email,
            address,
            customer_type,
            notes,
            COALESCE(is_active, 1) AS is_active,
            COALESCE(pricing_enabled, 0) AS pricing_enabled,
            COALESCE(default_price_type, 'selling') AS default_price_type,
            COALESCE(default_discount_percent, 0) AS default_discount_percent,
            pricing_note,
            created_at,
            updated_at,
            created_by,
            updated_by
        FROM customers
        WHERE id = ?
        LIMIT 1
        """,
        (parse_int(customer_id, 0),),
    ).fetchone()
    return dict(row) if row else None


def find_customer_by_phone(cursor, phone_normalized, excluding_id=None):
    create_customer_tables(cursor)
    phone_normalized = normalize_customer_phone(phone_normalized)
    if not phone_normalized:
        return None

    query = "SELECT * FROM customers WHERE phone_normalized = ?"
    args = [phone_normalized]
    if excluding_id is not None:
        query += " AND id != ?"
        args.append(parse_int(excluding_id, 0))
    query += " LIMIT 1"

    row = cursor.execute(query, args).fetchone()
    return dict(row) if row else None


def create_customer(cursor, body):
    create_customer_tables(cursor)

    name = str(body.get("name", "") or "").strip()
    if not name:
        return False, "Customer name is required", None

    phone = clean_optional_text(body.get("phone"))
    phone_normalized = normalize_customer_phone(phone)
    if phone_normalized:
        existing = find_customer_by_phone(cursor, phone_normalized)
        if existing:
            return False, f"A customer with this phone already exists: {existing.get('name')}", existing

    now = datetime.now().astimezone().isoformat()
    cursor.execute(
        """
        INSERT INTO customers (
            customer_code,
            name,
            phone,
            phone_normalized,
            email,
            address,
            customer_type,
            notes,
            is_active,
            pricing_enabled,
            default_price_type,
            default_discount_percent,
            pricing_note,
            created_at,
            updated_at,
            created_by,
            updated_by
        )
        VALUES (NULL, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            name,
            phone,
            phone_normalized or None,
            clean_optional_text(body.get("email")),
            clean_optional_text(body.get("address")),
            normalize_customer_type(body.get("customer_type")),
            clean_optional_text(body.get("notes")),
            1 if normalize_bool(body.get("pricing_enabled"), False) else 0,
            normalize_price_type(body.get("default_price_type")),
            max(0.0, min(parse_float(body.get("default_discount_percent"), 0.0), 100.0)),
            clean_optional_text(body.get("pricing_note")),
            now,
            now,
            parse_int(body.get("created_by"), 0) or None,
            parse_int(body.get("created_by"), 0) or None,
        ),
    )

    customer_id = cursor.lastrowid
    code = generate_customer_code(customer_id)
    cursor.execute(
        "UPDATE customers SET customer_code = ?, updated_at = ? WHERE id = ?",
        (code, now, customer_id),
    )
    return True, "success", get_customer_by_id(cursor, customer_id)


def update_customer(cursor, body):
    create_customer_tables(cursor)

    customer_id = parse_int(body.get("id", body.get("customer_id", 0)), 0)
    if customer_id <= 0:
        return False, "Invalid customer", None

    existing = get_customer_by_id(cursor, customer_id)
    if not existing:
        return False, "Customer not found", None

    name = str(body.get("name", "") or "").strip()
    if not name:
        return False, "Customer name is required", None

    phone = clean_optional_text(body.get("phone"))
    phone_normalized = normalize_customer_phone(phone)
    if phone_normalized:
        duplicate = find_customer_by_phone(cursor, phone_normalized, excluding_id=customer_id)
        if duplicate:
            return False, f"A customer with this phone already exists: {duplicate.get('name')}", duplicate

    now = datetime.now().astimezone().isoformat()
    cursor.execute(
        """
        UPDATE customers
        SET name = ?,
            phone = ?,
            phone_normalized = ?,
            email = ?,
            address = ?,
            customer_type = ?,
            notes = ?,
            is_active = ?,
            pricing_enabled = ?,
            default_price_type = ?,
            default_discount_percent = ?,
            pricing_note = ?,
            updated_at = ?,
            updated_by = ?
        WHERE id = ?
        """,
        (
            name,
            phone,
            phone_normalized or None,
            clean_optional_text(body.get("email")),
            clean_optional_text(body.get("address")),
            normalize_customer_type(body.get("customer_type")),
            clean_optional_text(body.get("notes")),
            1 if normalize_bool(body.get("is_active"), True) else 0,
            1 if normalize_bool(body.get("pricing_enabled"), existing.get("pricing_enabled", 0) == 1) else 0,
            normalize_price_type(body.get("default_price_type", existing.get("default_price_type", "selling"))),
            max(
                0.0,
                min(
                    parse_float(
                        body.get(
                            "default_discount_percent",
                            existing.get("default_discount_percent", 0.0),
                        ),
                        0.0,
                    ),
                    100.0,
                ),
            ),
            clean_optional_text(body.get("pricing_note", existing.get("pricing_note"))),
            now,
            parse_int(body.get("updated_by"), 0) or None,
            customer_id,
        ),
    )
    return True, "success", get_customer_by_id(cursor, customer_id)


def set_customer_active_status(cursor, body, is_active):
    create_customer_tables(cursor)

    customer_id = parse_int(body.get("id", body.get("customer_id", 0)), 0)
    if customer_id <= 0:
        return False, "Invalid customer", None

    existing = get_customer_by_id(cursor, customer_id)
    if not existing:
        return False, "Customer not found", None

    now = datetime.now().astimezone().isoformat()
    cursor.execute(
        """
        UPDATE customers
        SET is_active = ?,
            updated_at = ?,
            updated_by = ?
        WHERE id = ?
        """,
        (
            1 if is_active else 0,
            now,
            parse_int(body.get("updated_by"), 0) or None,
            customer_id,
        ),
    )
    return True, "success", get_customer_by_id(cursor, customer_id)



def create_customer_credit_tables(cursor):
    create_customer_tables(cursor)
    ensure_customer_sales_columns(cursor)

    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS customer_ledger (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            pos_ledger_id INTEGER,
            customer_id INTEGER NOT NULL,
            entry_type TEXT NOT NULL,
            debit REAL NOT NULL DEFAULT 0,
            credit REAL NOT NULL DEFAULT 0,
            balance_after REAL NOT NULL DEFAULT 0,
            reference_type TEXT,
            reference_id INTEGER,
            sale_id INTEGER,
            payment_id INTEGER,
            description TEXT,
            payment_method TEXT,
            performed_by TEXT,
            approved_by TEXT,
            created_at TEXT NOT NULL,
            voided_at TEXT,
            voided_by TEXT,
            void_reason TEXT
        )
        """
    )
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS customer_payments (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            pos_payment_id INTEGER,
            customer_id INTEGER NOT NULL,
            amount REAL NOT NULL,
            payment_method TEXT NOT NULL,
            reference_note TEXT,
            cashier_name TEXT,
            received_by TEXT,
            created_at TEXT NOT NULL,
            voided_at TEXT,
            voided_by TEXT,
            void_reason TEXT
        )
        """
    )
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_customer_ledger_customer ON customer_ledger(customer_id, created_at)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_customer_ledger_pos_id ON customer_ledger(pos_ledger_id)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_customer_payments_customer ON customer_payments(customer_id, created_at)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_customer_payments_pos_id ON customer_payments(pos_payment_id)")


def normalize_credit_status(value):
    normalized = str(value or "normal").strip().lower()
    if normalized in {"watchlist", "blocked"}:
        return normalized
    return "normal"


def upsert_customer_from_sync(cursor, data):
    create_customer_credit_tables(cursor)

    customer_id = parse_int(data.get("customer_id") or data.get("id"), 0)
    customer_code = clean_optional_text(data.get("customer_code") or data.get("customer_code_snapshot"))
    name = clean_optional_text(
        data.get("customer_name")
        or data.get("name")
        or data.get("customer_name_snapshot")
    )
    phone = clean_optional_text(
        data.get("customer_phone")
        or data.get("phone")
        or data.get("customer_phone_snapshot")
    )
    phone_normalized = normalize_customer_phone(
        data.get("customer_phone_normalized") or data.get("phone_normalized") or phone
    )

    existing = None
    if customer_id > 0:
        existing = cursor.execute("SELECT * FROM customers WHERE id = ?", (customer_id,)).fetchone()
    if existing is None and customer_code:
        existing = cursor.execute("SELECT * FROM customers WHERE customer_code = ?", (customer_code,)).fetchone()
    if existing is None and phone_normalized:
        existing = cursor.execute("SELECT * FROM customers WHERE phone_normalized = ?", (phone_normalized,)).fetchone()

    now = datetime.now().astimezone().isoformat()
    credit_enabled = 1 if normalize_bool(data.get("credit_enabled"), False) else 0
    credit_limit = parse_float(data.get("credit_limit"), 0.0)
    current_balance = parse_float(data.get("current_credit_balance"), 0.0)
    credit_status = normalize_credit_status(data.get("credit_status"))
    credit_note = clean_optional_text(data.get("credit_note"))
    pricing_enabled = 1 if normalize_bool(data.get("pricing_enabled"), False) else 0
    default_price_type = (
        normalize_price_type(data.get("default_price_type"))
        if data.get("default_price_type") is not None
        else None
    )
    default_discount_percent = max(
        0.0,
        min(parse_float(data.get("default_discount_percent"), 0.0), 100.0),
    )
    pricing_note = clean_optional_text(data.get("pricing_note"))

    if existing:
        resolved_id = parse_int(existing["id"], 0)
        cursor.execute(
            """
            UPDATE customers
            SET customer_code = COALESCE(?, customer_code),
                name = COALESCE(?, name),
                phone = COALESCE(?, phone),
                phone_normalized = COALESCE(?, phone_normalized),
                email = COALESCE(?, email),
                address = COALESCE(?, address),
                customer_type = COALESCE(?, customer_type),
                notes = COALESCE(?, notes),
                is_active = ?,
                credit_enabled = CASE WHEN ? IS NULL THEN credit_enabled ELSE ? END,
                credit_limit = CASE WHEN ? IS NULL THEN credit_limit ELSE ? END,
                current_credit_balance = CASE WHEN ? IS NULL THEN current_credit_balance ELSE ? END,
                credit_status = COALESCE(?, credit_status),
                credit_note = COALESCE(?, credit_note),
                pricing_enabled = CASE WHEN ? IS NULL THEN pricing_enabled ELSE ? END,
                default_price_type = COALESCE(?, default_price_type),
                default_discount_percent = CASE WHEN ? IS NULL THEN default_discount_percent ELSE ? END,
                pricing_note = COALESCE(?, pricing_note),
                updated_at = ?
            WHERE id = ?
            """,
            (
                customer_code,
                name,
                phone,
                phone_normalized or None,
                clean_optional_text(data.get("customer_email") or data.get("email")),
                clean_optional_text(data.get("customer_address") or data.get("address")),
                normalize_customer_type(data.get("customer_type")),
                clean_optional_text(data.get("customer_notes") or data.get("notes")),
                1 if normalize_bool(data.get("customer_is_active"), True) else 0,
                data.get("credit_enabled"), credit_enabled,
                data.get("credit_limit"), credit_limit,
                data.get("current_credit_balance"), current_balance,
                credit_status,
                credit_note,
                data.get("pricing_enabled"), pricing_enabled,
                default_price_type or "selling",
                data.get("default_discount_percent"), default_discount_percent,
                pricing_note,
                now,
                resolved_id,
            ),
        )
        return resolved_id

    if not name:
        name = f"Customer {customer_code or customer_id or 'Unknown'}"
    if not customer_code and customer_id > 0:
        customer_code = generate_customer_code(customer_id)

    if customer_id > 0:
        cursor.execute(
            """
            INSERT INTO customers (
                id, customer_code, name, phone, phone_normalized, email, address,
                customer_type, notes, is_active, credit_enabled, credit_limit,
                current_credit_balance, credit_status, credit_note,
                pricing_enabled, default_price_type, default_discount_percent, pricing_note,
                created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                customer_id,
                customer_code,
                name,
                phone,
                phone_normalized or None,
                clean_optional_text(data.get("customer_email") or data.get("email")),
                clean_optional_text(data.get("customer_address") or data.get("address")),
                normalize_customer_type(data.get("customer_type")),
                clean_optional_text(data.get("customer_notes") or data.get("notes")),
                1 if normalize_bool(data.get("customer_is_active"), True) else 0,
                credit_enabled,
                credit_limit,
                current_balance,
                credit_status,
                credit_note,
                pricing_enabled,
                default_price_type,
                default_discount_percent,
                pricing_note,
                now,
                now,
            ),
        )
        return customer_id

    cursor.execute(
        """
        INSERT INTO customers (
            customer_code, name, phone, phone_normalized, email, address,
            customer_type, notes, is_active, credit_enabled, credit_limit,
            current_credit_balance, credit_status, credit_note,
            pricing_enabled, default_price_type, default_discount_percent, pricing_note,
            created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            customer_code,
            name,
            phone,
            phone_normalized or None,
            clean_optional_text(data.get("customer_email") or data.get("email")),
            clean_optional_text(data.get("customer_address") or data.get("address")),
            normalize_customer_type(data.get("customer_type")),
            clean_optional_text(data.get("customer_notes") or data.get("notes")),
            1 if normalize_bool(data.get("customer_is_active"), True) else 0,
            credit_enabled,
            credit_limit,
            current_balance,
            credit_status,
            credit_note,
            pricing_enabled,
            default_price_type or "selling",
            default_discount_percent,
            pricing_note,
            now,
            now,
        ),
    )
    new_id = cursor.lastrowid
    if not customer_code:
        cursor.execute(
            "UPDATE customers SET customer_code = ? WHERE id = ?",
            (generate_customer_code(new_id), new_id),
        )
    return new_id


def customer_credit_balance(cursor, customer_id):
    create_customer_credit_tables(cursor)
    row = cursor.execute(
        """
        SELECT COALESCE(SUM(COALESCE(debit, 0) - COALESCE(credit, 0)), 0) AS balance
        FROM customer_ledger
        WHERE customer_id = ?
        """,
        (parse_int(customer_id, 0),),
    ).fetchone()
    return round(parse_float(row["balance"] if row else 0, 0.0), 2)


def update_customer_cached_credit_balance(cursor, customer_id, balance=None):
    if balance is None:
        balance = customer_credit_balance(cursor, customer_id)
    cursor.execute(
        "UPDATE customers SET current_credit_balance = ?, updated_at = ? WHERE id = ?",
        (round(parse_float(balance, 0.0), 2), datetime.now().astimezone().isoformat(), parse_int(customer_id, 0)),
    )
    return round(parse_float(balance, 0.0), 2)


def insert_credit_ledger_entry(cursor, data, customer_id=None):
    create_customer_credit_tables(cursor)
    ledger = data.get("ledger_entry") if isinstance(data.get("ledger_entry"), dict) else data
    resolved_customer_id = parse_int(customer_id or data.get("customer_id") or ledger.get("customer_id"), 0)
    if resolved_customer_id <= 0:
        resolved_customer_id = upsert_customer_from_sync(cursor, data)

    pos_ledger_id = parse_int(ledger.get("ledger_id") or ledger.get("pos_ledger_id"), 0) or None
    entry_type = str(ledger.get("entry_type") or data.get("entry_type") or "adjustment").strip().lower()
    sale_id = parse_int(ledger.get("sale_id") or data.get("sale_id") or data.get("refund_sale_id"), 0) or None
    payment_id = parse_int(ledger.get("payment_id") or data.get("payment_id"), 0) or None

    if pos_ledger_id:
        existing = cursor.execute(
            "SELECT id FROM customer_ledger WHERE pos_ledger_id = ? LIMIT 1",
            (pos_ledger_id,),
        ).fetchone()
        if existing:
            return parse_int(existing["id"], 0)

    if entry_type in {"credit_sale", "refund"} and sale_id:
        existing = cursor.execute(
            "SELECT id FROM customer_ledger WHERE entry_type = ? AND sale_id = ? LIMIT 1",
            (entry_type, sale_id),
        ).fetchone()
        if existing:
            return parse_int(existing["id"], 0)

    if entry_type == "payment" and payment_id:
        existing = cursor.execute(
            "SELECT id FROM customer_ledger WHERE entry_type = ? AND payment_id = ? LIMIT 1",
            (entry_type, payment_id),
        ).fetchone()
        if existing:
            return parse_int(existing["id"], 0)

    cursor.execute(
        """
        INSERT INTO customer_ledger (
            pos_ledger_id, customer_id, entry_type, debit, credit, balance_after,
            reference_type, reference_id, sale_id, payment_id, description,
            payment_method, performed_by, approved_by, created_at,
            voided_at, voided_by, void_reason
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            pos_ledger_id,
            resolved_customer_id,
            entry_type,
            parse_float(ledger.get("debit") if ledger.get("debit") is not None else data.get("debit"), 0.0),
            parse_float(ledger.get("credit") if ledger.get("credit") is not None else data.get("credit"), 0.0),
            parse_float(ledger.get("balance_after") if ledger.get("balance_after") is not None else data.get("credit_new_balance") or data.get("new_balance"), 0.0),
            clean_optional_text(ledger.get("reference_type") or data.get("reference_type")),
            parse_int(ledger.get("reference_id") or data.get("reference_id"), 0) or None,
            sale_id,
            payment_id,
            clean_optional_text(ledger.get("description") or data.get("description")),
            clean_optional_text(ledger.get("payment_method") or data.get("payment_method")),
            clean_optional_text(ledger.get("performed_by") or data.get("performed_by")),
            clean_optional_text(ledger.get("approved_by") or data.get("approved_by")),
            clean_optional_text(ledger.get("created_at") or data.get("created_at")) or datetime.now().astimezone().isoformat(),
            clean_optional_text(ledger.get("voided_at") or data.get("voided_at")),
            clean_optional_text(ledger.get("voided_by") or data.get("voided_by")),
            clean_optional_text(ledger.get("void_reason") or data.get("void_reason")),
        ),
    )
    update_customer_cached_credit_balance(cursor, resolved_customer_id, data.get("credit_new_balance") or data.get("new_balance") or ledger.get("balance_after"))
    return cursor.lastrowid


def handle_credit_settings_sync(cursor, data):
    customer_id = upsert_customer_from_sync(cursor, data)
    cursor.execute(
        """
        UPDATE customers
        SET credit_enabled = ?, credit_limit = ?, current_credit_balance = ?,
            credit_status = ?, credit_note = ?, updated_at = ?
        WHERE id = ?
        """,
        (
            1 if normalize_bool(data.get("credit_enabled"), False) else 0,
            parse_float(data.get("credit_limit"), 0.0),
            parse_float(data.get("current_credit_balance"), 0.0),
            normalize_credit_status(data.get("credit_status")),
            clean_optional_text(data.get("credit_note")),
            clean_optional_text(data.get("updated_at")) or datetime.now().astimezone().isoformat(),
            customer_id,
        ),
    )
    return customer_id


def handle_customer_pricing_settings_sync(cursor, data):
    customer_id = upsert_customer_from_sync(cursor, data)
    cursor.execute(
        """
        UPDATE customers
        SET pricing_enabled = ?,
            default_price_type = ?,
            default_discount_percent = ?,
            pricing_note = ?,
            updated_at = ?
        WHERE id = ?
        """,
        (
            1 if normalize_bool(data.get("pricing_enabled"), False) else 0,
            normalize_price_type(data.get("default_price_type")),
            max(0.0, min(parse_float(data.get("default_discount_percent"), 0.0), 100.0)),
            clean_optional_text(data.get("pricing_note")),
            datetime.now().astimezone().isoformat(),
            customer_id,
        ),
    )
    return customer_id


def handle_customer_product_price_sync(cursor, data):
    create_customer_product_prices_table(cursor)
    customer_id = parse_int(data.get("customer_id"), 0)
    if customer_id <= 0:
        customer_id = upsert_customer_from_sync(cursor, data)
    if customer_id <= 0:
        raise ValueError("Invalid customer for product price sync")

    barcode = str(data.get("barcode") or "").strip()
    if not barcode:
        raise ValueError("Product barcode is required")

    product_name = str(data.get("product_name_snapshot") or data.get("product_name") or barcode).strip()
    fixed_price = max(0.0, parse_float(data.get("fixed_price"), 0.0))
    is_active = 1 if normalize_bool(data.get("is_active"), True) else 0
    note = clean_optional_text(data.get("note"))
    now = datetime.now().astimezone().isoformat()
    created_at = str(data.get("created_at") or now)
    updated_at = str(data.get("updated_at") or now)
    remote_id = parse_int(data.get("customer_product_price_id") or data.get("id"), 0)

    existing = None
    if remote_id > 0:
        existing = cursor.execute(
            "SELECT id FROM customer_product_prices WHERE id = ? LIMIT 1",
            (remote_id,),
        ).fetchone()
    if existing is None:
        existing = cursor.execute(
            "SELECT id FROM customer_product_prices WHERE customer_id = ? AND barcode = ? LIMIT 1",
            (customer_id, barcode),
        ).fetchone()

    if existing:
        resolved_id = parse_int(existing["id"], 0)
        cursor.execute(
            """
            UPDATE customer_product_prices
            SET customer_id = ?,
                barcode = ?,
                product_name_snapshot = ?,
                fixed_price = ?,
                is_active = ?,
                note = ?,
                updated_at = ?,
                updated_by = ?
            WHERE id = ?
            """,
            (
                customer_id,
                barcode,
                product_name,
                fixed_price,
                is_active,
                note,
                updated_at,
                parse_int(data.get("updated_by"), 0) or None,
                resolved_id,
            ),
        )
        return resolved_id

    if remote_id > 0:
        cursor.execute(
            """
            INSERT INTO customer_product_prices (
                id, customer_id, barcode, product_name_snapshot, fixed_price,
                is_active, note, created_at, updated_at, created_by, updated_by
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                remote_id,
                customer_id,
                barcode,
                product_name,
                fixed_price,
                is_active,
                note,
                created_at,
                updated_at,
                parse_int(data.get("created_by"), 0) or None,
                parse_int(data.get("updated_by"), 0) or None,
            ),
        )
        return remote_id

    cursor.execute(
        """
        INSERT INTO customer_product_prices (
            customer_id, barcode, product_name_snapshot, fixed_price,
            is_active, note, created_at, updated_at, created_by, updated_by
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            customer_id,
            barcode,
            product_name,
            fixed_price,
            is_active,
            note,
            created_at,
            updated_at,
            parse_int(data.get("created_by"), 0) or None,
            parse_int(data.get("updated_by"), 0) or None,
        ),
    )
    return cursor.lastrowid


def handle_credit_sale_update_sync(cursor, data):
    customer_id = upsert_customer_from_sync(cursor, data)
    ledger_id = insert_credit_ledger_entry(cursor, data, customer_id=customer_id)
    sale_id = parse_int(data.get("sale_id"), 0)
    if sale_id > 0:
        cursor.execute(
            """
            UPDATE sales
            SET payment_method = 'customer_credit',
                is_credit_sale = 1,
                credit_status = ?,
                credit_ledger_id = ?,
                credit_approved_by = ?,
                credit_previous_balance = ?,
                credit_new_balance = ?,
                credit_bill_amount = ?,
                credit_limit_snapshot = ?,
                customer_id = ?,
                customer_name_snapshot = COALESCE(?, customer_name_snapshot),
                customer_phone_snapshot = COALESCE(?, customer_phone_snapshot),
                customer_code_snapshot = COALESCE(?, customer_code_snapshot)
            WHERE id = ? OR pos_sale_id = ?
            """,
            (
                clean_optional_text(data.get("credit_status")) or "posted",
                ledger_id,
                clean_optional_text(data.get("credit_approved_by")),
                parse_float(data.get("credit_previous_balance"), 0.0),
                parse_float(data.get("credit_new_balance"), 0.0),
                parse_float(data.get("credit_bill_amount"), 0.0),
                parse_float(data.get("credit_limit_snapshot"), 0.0),
                customer_id,
                clean_optional_text(data.get("customer_name") or data.get("customer_name_snapshot")),
                clean_optional_text(data.get("customer_phone") or data.get("customer_phone_snapshot")),
                clean_optional_text(data.get("customer_code") or data.get("customer_code_snapshot")),
                sale_id,
                sale_id,
            ),
        )
    return ledger_id


def handle_credit_refund_update_sync(cursor, data):
    customer_id = upsert_customer_from_sync(cursor, data)
    ledger_id = insert_credit_ledger_entry(cursor, data, customer_id=customer_id)
    refund_sale_id = parse_int(data.get("refund_sale_id") or data.get("sale_id"), 0)
    if refund_sale_id > 0:
        cursor.execute(
            """
            UPDATE sales
            SET payment_method = COALESCE(payment_method, 'customer_credit_refund'),
                is_credit_sale = 1,
                credit_status = ?,
                credit_ledger_id = ?,
                credit_approved_by = ?,
                credit_previous_balance = ?,
                credit_new_balance = ?,
                credit_bill_amount = ?,
                credit_limit_snapshot = ?,
                customer_id = ?,
                customer_name_snapshot = COALESCE(?, customer_name_snapshot),
                customer_phone_snapshot = COALESCE(?, customer_phone_snapshot),
                customer_code_snapshot = COALESCE(?, customer_code_snapshot)
            WHERE id = ? OR pos_sale_id = ?
            """,
            (
                clean_optional_text(data.get("credit_status")) or "refund_posted",
                ledger_id,
                clean_optional_text(data.get("credit_approved_by")),
                parse_float(data.get("credit_previous_balance"), 0.0),
                parse_float(data.get("credit_new_balance"), 0.0),
                parse_float(data.get("credit_bill_amount"), 0.0),
                parse_float(data.get("credit_limit_snapshot"), 0.0),
                customer_id,
                clean_optional_text(data.get("customer_name") or data.get("customer_name_snapshot")),
                clean_optional_text(data.get("customer_phone") or data.get("customer_phone_snapshot")),
                clean_optional_text(data.get("customer_code") or data.get("customer_code_snapshot")),
                refund_sale_id,
                refund_sale_id,
            ),
        )
    return ledger_id


def handle_customer_payment_sync(cursor, data):
    customer_id = upsert_customer_from_sync(cursor, data)
    pos_payment_id = parse_int(data.get("payment_id"), 0) or None
    if pos_payment_id:
        existing = cursor.execute(
            "SELECT id FROM customer_payments WHERE pos_payment_id = ? LIMIT 1",
            (pos_payment_id,),
        ).fetchone()
        if existing:
            return parse_int(existing["id"], 0)

    cursor.execute(
        """
        INSERT INTO customer_payments (
            pos_payment_id, customer_id, amount, payment_method, reference_note,
            cashier_name, received_by, created_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            pos_payment_id,
            customer_id,
            parse_float(data.get("amount"), 0.0),
            clean_optional_text(data.get("payment_method")) or "cash",
            clean_optional_text(data.get("reference_note")),
            clean_optional_text(data.get("cashier_name")),
            clean_optional_text(data.get("received_by")),
            clean_optional_text(data.get("created_at")) or datetime.now().astimezone().isoformat(),
        ),
    )
    insert_credit_ledger_entry(cursor, data, customer_id=customer_id)
    return cursor.lastrowid


def handle_customer_payment_void_sync(cursor, data):
    customer_id = upsert_customer_from_sync(cursor, data)
    pos_payment_id = parse_int(data.get("payment_id"), 0)
    if pos_payment_id > 0:
        cursor.execute(
            """
            UPDATE customer_payments
            SET voided_at = ?, voided_by = ?, void_reason = ?
            WHERE pos_payment_id = ? OR id = ?
            """,
            (
                clean_optional_text(data.get("voided_at")) or datetime.now().astimezone().isoformat(),
                clean_optional_text(data.get("voided_by")),
                clean_optional_text(data.get("void_reason")),
                pos_payment_id,
                pos_payment_id,
            ),
        )
        cursor.execute(
            """
            UPDATE customer_ledger
            SET voided_at = ?, voided_by = ?, void_reason = ?
            WHERE entry_type = 'payment' AND (payment_id = ? OR pos_ledger_id = ?)
            """,
            (
                clean_optional_text(data.get("voided_at")) or datetime.now().astimezone().isoformat(),
                clean_optional_text(data.get("voided_by")),
                clean_optional_text(data.get("void_reason")),
                pos_payment_id,
                pos_payment_id,
            ),
        )
    return insert_credit_ledger_entry(cursor, data, customer_id=customer_id)


def get_customer_ledger_rows(cursor, customer_id, limit=300):
    create_customer_credit_tables(cursor)
    return [
        dict(row)
        for row in cursor.execute(
            """
            SELECT *
            FROM customer_ledger
            WHERE customer_id = ?
            ORDER BY datetime(created_at) DESC, id DESC
            LIMIT ?
            """,
            (parse_int(customer_id, 0), parse_int(limit, 300)),
        ).fetchall()
    ]


def get_credit_customers_report_rows(cursor, include_zero=False, limit=300):
    create_customer_credit_tables(cursor)
    where = "(COALESCE(c.credit_enabled, 0) = 1 OR ABS(COALESCE(c.current_credit_balance, 0)) > 0)" if include_zero else "ABS(COALESCE(c.current_credit_balance, 0)) > 0"
    return [
        dict(row)
        for row in cursor.execute(
            f"""
            SELECT
                c.id,
                c.customer_code,
                c.name,
                c.phone,
                c.customer_type,
                c.is_active,
                COALESCE(c.credit_enabled, 0) AS credit_enabled,
                COALESCE(c.credit_limit, 0) AS credit_limit,
                COALESCE(c.current_credit_balance, 0) AS current_credit_balance,
                COALESCE(c.credit_status, 'normal') AS credit_status,
                c.credit_note,
                (
                  SELECT MAX(l.created_at)
                  FROM customer_ledger l
                  WHERE l.customer_id = c.id AND l.entry_type = 'payment'
                ) AS last_payment_at,
                (
                  SELECT MAX(l.created_at)
                  FROM customer_ledger l
                  WHERE l.customer_id = c.id AND l.entry_type = 'credit_sale'
                ) AS last_credit_sale_at
            FROM customers c
            WHERE {where}
            ORDER BY COALESCE(c.current_credit_balance, 0) DESC, c.name COLLATE NOCASE ASC
            LIMIT ?
            """,
            (parse_int(limit, 300),),
        ).fetchall()
    ]

def get_customer_summary(cursor, customer_id):
    ensure_customer_sales_columns(cursor)
    customer_id = parse_int(customer_id, 0)

    row = cursor.execute(
        """
        SELECT
            COUNT(*) AS transaction_count,
            COALESCE(SUM(CASE
                WHEN LOWER(COALESCE(transaction_type, 'sale')) = 'refund'
                THEN -ABS(COALESCE(total_amount, 0))
                ELSE ABS(COALESCE(total_amount, 0))
            END), 0) AS net_total_spent,
            COALESCE(SUM(CASE
                WHEN LOWER(COALESCE(transaction_type, 'sale')) = 'refund'
                THEN 1 ELSE 0
            END), 0) AS refund_count,
            COALESCE(SUM(CASE
                WHEN LOWER(COALESCE(transaction_type, 'sale')) = 'refund'
                THEN 0 ELSE 1
            END), 0) AS sale_count,
            MAX(created_at) AS last_purchase_at,
            MIN(created_at) AS first_purchase_at
        FROM sales
        WHERE customer_id = ?
        """,
        (customer_id,),
    ).fetchone()

    sale_count = parse_int(row["sale_count"] if row else 0, 0)
    net_total = parse_float(row["net_total_spent"] if row else 0, 0.0)

    return {
        "transaction_count": parse_int(row["transaction_count"] if row else 0, 0),
        "sale_count": sale_count,
        "refund_count": parse_int(row["refund_count"] if row else 0, 0),
        "net_total_spent": round(net_total, 2),
        "average_sale": round(net_total / sale_count, 2) if sale_count > 0 else 0.0,
        "first_purchase_at": row["first_purchase_at"] if row else None,
        "last_purchase_at": row["last_purchase_at"] if row else None,
    }


def get_customer_purchase_history(cursor, customer_id, limit=100):
    ensure_customer_sales_columns(cursor)
    customer_id = parse_int(customer_id, 0)
    limit = parse_int(limit, 100)
    if limit <= 0:
        limit = 100
    if limit > 500:
        limit = 500

    rows = cursor.execute(
        """
        SELECT *
        FROM sales
        WHERE customer_id = ?
        ORDER BY datetime(created_at) DESC, id DESC
        LIMIT ?
        """,
        (customer_id, limit),
    ).fetchall()
    return [dict(row) for row in rows]



def get_product_row(cursor, barcode):
    return cursor.execute(
        """
        SELECT
            id,
            barcode,
            name,
            COALESCE(category, 'General') AS category,
            CASE
                WHEN LOWER(COALESCE(quantity_type, '')) = 'weight' THEN 'weight'
                ELSE 'unit'
            END AS quantity_type,
            CASE
                WHEN TRIM(COALESCE(unit_label, '')) != '' THEN TRIM(unit_label)
                WHEN LOWER(COALESCE(quantity_type, 'unit')) = 'weight' THEN 'kg'
                ELSE 'pcs'
            END AS unit_label,
            COALESCE(cost_price, 0) AS cost_price,
            COALESCE(selling_price, price, 0) AS selling_price,
            COALESCE(price, selling_price, 0) AS price,
            CASE
                WHEN COALESCE(wholesale_price, 0) <= 0 THEN COALESCE(selling_price, price, 0)
                ELSE wholesale_price
            END AS wholesale_price,
            sale_price,
            COALESCE(sale_enabled, CASE WHEN sale_price IS NOT NULL THEN 1 ELSE 0 END) AS sale_enabled,
            COALESCE(stock, 0) AS stock,
            COALESCE(min_stock_level, 0) AS min_stock_level,
            COALESCE(is_active, 1) AS is_active,
            updated_at,
            last_price_updated_at
        FROM products
        WHERE barcode = ?
        """,
        (barcode,),
    ).fetchone()


def ensure_pos_inventory_movements_table(cursor):
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS inventory_movements (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            barcode TEXT NOT NULL,
            product_name TEXT NOT NULL,
            action_type TEXT NOT NULL,
            quantity_change INTEGER,
            stock_before INTEGER,
            stock_after INTEGER,
            old_price REAL,
            new_price REAL,
            price_type TEXT,
            reason TEXT,
            reference_id INTEGER,
            reference_type TEXT,
            performed_by TEXT,
            created_at TEXT NOT NULL
        )
        """
    )


def mirror_inventory_movement_to_pos(
    *,
    barcode,
    product_name,
    action_type,
    quantity_change=None,
    stock_before=None,
    stock_after=None,
    old_price=None,
    new_price=None,
    price_type=None,
    reason="",
    reference_id=None,
    reference_type="backend_history",
    performed_by="Admin App",
    created_at=None,
):
    if not os.path.exists(POS_DB_PATH):
        return

    barcode = str(barcode or "").strip()
    action_type = str(action_type or "").strip()
    if not barcode or not action_type:
        return

    conn = None
    try:
        conn = get_pos_db()
        cursor = conn.cursor()
        ensure_pos_inventory_movements_table(cursor)

        resolved_product_name = str(product_name or "").strip()
        if not resolved_product_name:
            row = cursor.execute(
                "SELECT name FROM products WHERE barcode = ? LIMIT 1",
                (barcode,),
            ).fetchone()
            resolved_product_name = str((row["name"] if row else "Unknown product") or "Unknown product")

        safe_reference_type = str(reference_type or "backend_history").strip() or "backend_history"
        mirror_created_at = created_at or datetime.now().strftime("%Y-%m-%d %H:%M:%S")

        existing = cursor.execute(
            """
            SELECT id
            FROM inventory_movements
            WHERE barcode = ?
              AND action_type = ?
              AND COALESCE(reference_type, '') = ?
              AND COALESCE(reference_id, -1) = COALESCE(?, -1)
            LIMIT 1
            """,
            (barcode, action_type, safe_reference_type, reference_id),
        ).fetchone()
        if existing:
            return

        # Prevent POS-origin movements from being mirrored back as duplicate
        # Product History records.
        #
        # Example:
        # 1) POS receives stock and immediately writes a local inventory movement.
        # 2) POS sync sends the same receive to this local server.
        # 3) The server updates local_admin.db and mirrors the backend history into
        #    the POS DB again.
        #
        # The normal reference_id/reference_type duplicate check above will not catch
        # that case because the local POS row and backend mirror row have different
        # references. This second check compares the real movement details instead.
        equivalent_existing = cursor.execute(
            """
            SELECT id
            FROM inventory_movements
            WHERE barcode = ?
              AND action_type = ?
              AND COALESCE(CAST(quantity_change AS REAL), -999999999.0) =
                  COALESCE(CAST(? AS REAL), -999999999.0)
              AND COALESCE(CAST(stock_before AS REAL), -999999999.0) =
                  COALESCE(CAST(? AS REAL), -999999999.0)
              AND COALESCE(CAST(stock_after AS REAL), -999999999.0) =
                  COALESCE(CAST(? AS REAL), -999999999.0)
              AND (
                    COALESCE(
                        ABS(
                            strftime('%s', REPLACE(created_at, 'T', ' ')) -
                            strftime('%s', REPLACE(?, 'T', ' '))
                        ),
                        999999999
                    ) <= 120
                    OR created_at = ?
                  )
            LIMIT 1
            """,
            (
                barcode,
                action_type,
                quantity_change,
                stock_before,
                stock_after,
                mirror_created_at,
                mirror_created_at,
            ),
        ).fetchone()
        if equivalent_existing:
            return

        cursor.execute(
            """
            INSERT INTO inventory_movements (
                barcode,
                product_name,
                action_type,
                quantity_change,
                stock_before,
                stock_after,
                old_price,
                new_price,
                price_type,
                reason,
                reference_id,
                reference_type,
                performed_by,
                created_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                barcode,
                resolved_product_name,
                action_type,
                quantity_change,
                stock_before,
                stock_after,
                old_price,
                new_price,
                price_type,
                reason,
                reference_id,
                safe_reference_type,
                str(performed_by or "Admin App").strip() or "Admin App",
                mirror_created_at,
            ),
        )
        conn.commit()
    except Exception as e:
        print(f"  ⚠️ POS inventory mirror warning: {e}")
    finally:
        if conn is not None:
            try:
                conn.close()
            except Exception:
                pass


def log_inventory_history(
    cursor,
    barcode,
    movement_type,
    quantity,
    reason="",
    reference_type="",
    reference_id=None,
):
    created_at = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    cursor.execute(
        """
        INSERT INTO inventory_history (
            barcode,
            movement_type,
            quantity,
            reason,
            reference_type,
            reference_id,
            created_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?)
        """,
        (
            barcode,
            movement_type,
            quantity,
            reason,
            reference_type,
            reference_id,
            created_at,
        ),
    )
    return {
        "id": cursor.lastrowid,
        "created_at": created_at,
    }


def update_product_price(
    cursor,
    barcode,
    new_price,
    price_type="selling",
    sale_enabled=None,
    reason="",
):
    row = get_product_row(cursor, barcode)
    if not row:
        return False, "Product not found"

    normalized = str(price_type or "selling").strip().lower()
    if normalized not in {"selling", "wholesale", "sale", "cost"}:
        normalized = "selling"

    new_price = parse_float(new_price, -1)
    if new_price < 0:
        return False, "Invalid price"

    product_name = str(row["name"] or "Unknown product")
    old_price = parse_float(
        row["cost_price"] if normalized == "cost"
        else row["wholesale_price"] if normalized == "wholesale"
        else row["sale_price"] if normalized == "sale"
        else row["selling_price"],
        0,
    )

    if normalized == "selling":
        cursor.execute(
            f"""
            UPDATE products
            SET price = ?,
                selling_price = ?,
                updated_at = {now_sql()},
                last_price_updated_at = {now_sql()}
            WHERE barcode = ?
            """,
            (new_price, new_price, barcode),
        )
    elif normalized == "wholesale":
        cursor.execute(
            f"""
            UPDATE products
            SET wholesale_price = ?,
                updated_at = {now_sql()},
                last_price_updated_at = {now_sql()}
            WHERE barcode = ?
            """,
            (new_price, barcode),
        )
    elif normalized == "sale":
        enabled_value = 1 if normalize_bool(sale_enabled, True) else 0
        cursor.execute(
            f"""
            UPDATE products
            SET sale_price = ?,
                sale_enabled = ?,
                updated_at = {now_sql()},
                last_price_updated_at = {now_sql()}
            WHERE barcode = ?
            """,
            (new_price, enabled_value, barcode),
        )
    else:  # cost
        cursor.execute(
            f"""
            UPDATE products
            SET cost_price = ?,
                updated_at = {now_sql()},
                last_price_updated_at = {now_sql()}
            WHERE barcode = ?
            """,
            (new_price, barcode),
        )

    history_entry = log_inventory_history(
        cursor,
        barcode=barcode,
        movement_type=f"price_change_{normalized}",
        quantity=0,
        reason=reason or f"{normalized.title()} price updated to Rs.{new_price:.2f}",
        reference_type="price_update",
        reference_id=None,
    )

    mirror_inventory_movement_to_pos(
        barcode=barcode,
        product_name=product_name,
        action_type=f"price_change_{normalized}",
        old_price=old_price,
        new_price=new_price,
        price_type=normalized,
        reason=reason or f"{normalized.title()} price updated to Rs.{new_price:.2f}",
        reference_id=history_entry["id"],
        reference_type="backend_history",
        performed_by="Admin App",
        created_at=history_entry["created_at"],
    )
    return True, "success"


def update_stock_receive(
    cursor,
    barcode,
    quantity,
    cost=0,
    supplier_id=0,
    supplier_name="",
    reason="",
):
    row = get_product_row(cursor, barcode)
    if not row:
        return False, "Product not found", None

    quantity = round_quantity(quantity)
    if quantity <= 0:
        return False, "Quantity must be greater than 0", None

    cost = parse_float(cost, 0)
    product_name = str(row["name"] or "Unknown product")
    stock_before = round_quantity(row["stock"])
    stock_after = round_quantity(stock_before + quantity)

    supplier_id = parse_int(supplier_id, 0)

    cursor.execute(
        f"""
        INSERT INTO stock_receipts (
            barcode,
            quantity,
            supplier_id,
            cost,
            created_at
        )
        VALUES (?, ?, ?, ?, {now_sql()})
        """,
        (barcode, quantity, supplier_id, cost),
    )
    receipt_id = cursor.lastrowid

    if supplier_id > 0:
        _upsert_supplier_product_mapping(
            cursor,
            barcode=barcode,
            supplier_id=supplier_id,
        )

    if cost > 0:
        cursor.execute(
            f"""
            UPDATE products
            SET stock = stock + ?,
                cost_price = ?,
                updated_at = {now_sql()},
                last_price_updated_at = {now_sql()}
            WHERE barcode = ?
            """,
            (quantity, cost, barcode),
        )
    else:
        cursor.execute(
            f"""
            UPDATE products
            SET stock = stock + ?,
                updated_at = {now_sql()}
            WHERE barcode = ?
            """,
            (quantity, barcode),
        )

    note = reason or "Received stock"
    if supplier_name:
        note = f"{note} ({supplier_name})"

    history_entry = log_inventory_history(
        cursor,
        barcode=barcode,
        movement_type="stock_in",
        quantity=quantity,
        reason=note,
        reference_type="stock_receipt",
        reference_id=receipt_id,
    )

    mirror_inventory_movement_to_pos(
        barcode=barcode,
        product_name=product_name,
        action_type="stock_receive",
        quantity_change=quantity,
        stock_before=stock_before,
        stock_after=stock_after,
        reason=note,
        reference_id=history_entry["id"],
        reference_type="backend_history",
        performed_by="Admin App",
        created_at=history_entry["created_at"],
    )
    return True, "success", receipt_id


def update_stock_adjustment(cursor, barcode, adjustment_type, quantity, reason=""):
    row = get_product_row(cursor, barcode)
    if not row:
        return False, "Product not found", None, None

    current_stock = round_quantity(row["stock"])
    product_name = str(row["name"] or "Unknown product")
    normalized = str(adjustment_type or "").strip().lower()
    quantity = round_quantity(quantity)

    if normalized in {"increase", "add"}:
        if quantity <= 0:
            return False, "Quantity must be greater than 0", None, None
        stock_delta = quantity
        movement_type = "stock_adjust_add"
    elif normalized in {"decrease", "remove"}:
        if quantity <= 0:
            return False, "Quantity must be greater than 0", None, None
        stock_delta = -quantity
        movement_type = "stock_adjust_remove"
    elif normalized in {"set_exact", "set"}:
        if quantity < 0:
            return False, "Quantity cannot be negative", None, None
        stock_delta = round_quantity(quantity - current_stock)
        movement_type = "stock_adjust_set"
    else:
        return False, "Invalid adjustment type", None, None

    resulting_stock = round_quantity(current_stock + stock_delta)
    if resulting_stock < 0:
        return False, "Resulting stock cannot be negative", None, None
    if abs(stock_delta) < 0.000001:
        return False, "No stock change detected", current_stock, 0

    cursor.execute(
        f"""
        UPDATE products
        SET stock = ?, updated_at = {now_sql()}
        WHERE barcode = ?
        """,
        (resulting_stock, barcode),
    )

    note = reason or "Manual stock adjustment"
    history_entry = log_inventory_history(
        cursor,
        barcode=barcode,
        movement_type=movement_type,
        quantity=stock_delta,
        reason=note,
        reference_type="manual_adjustment",
        reference_id=None,
    )

    mirror_inventory_movement_to_pos(
        barcode=barcode,
        product_name=product_name,
        action_type=movement_type,
        quantity_change=stock_delta,
        stock_before=current_stock,
        stock_after=resulting_stock,
        reason=note,
        reference_id=history_entry["id"],
        reference_type="backend_history",
        performed_by="Admin App",
        created_at=history_entry["created_at"],
    )
    return True, "success", resulting_stock, stock_delta


def update_min_stock_level(cursor, barcode, min_stock_level, reason=""):
    row = get_product_row(cursor, barcode)
    if not row:
        return False, "Product not found"

    min_stock_level = parse_int(min_stock_level, -1)
    if min_stock_level < 0:
        return False, "Minimum stock level cannot be negative"

    product_name = str(row["name"] or "Unknown product")

    cursor.execute(
        f"""
        UPDATE products
        SET min_stock_level = ?, updated_at = {now_sql()}
        WHERE barcode = ?
        """,
        (min_stock_level, barcode),
    )

    note = reason or f"Minimum stock level updated to {min_stock_level}"
    history_entry = log_inventory_history(
        cursor,
        barcode=barcode,
        movement_type="min_stock_change",
        quantity=0,
        reason=note,
        reference_type="min_stock_update",
        reference_id=None,
    )

    mirror_inventory_movement_to_pos(
        barcode=barcode,
        product_name=product_name,
        action_type="min_stock_change",
        reason=note,
        reference_id=history_entry["id"],
        reference_type="backend_history",
        performed_by="Admin App",
        created_at=history_entry["created_at"],
    )
    return True, "success"




def create_or_update_product(
    cursor,
    barcode,
    name,
    category="General",
    cost_price=0,
    selling_price=0,
    wholesale_price=None,
    sale_price=None,
    sale_enabled=False,
    quantity_type="unit",
    unit_label=None,
    opening_stock=0,
    min_stock_level=0,
    reason="",
    mirror_to_pos=True,
):
    barcode = str(barcode or "").strip()
    name = str(name or "").strip()
    category = str(category or "General").strip() or "General"
    quantity_type = normalize_quantity_type(quantity_type)
    unit_label = normalize_unit_label(quantity_type, unit_label)

    if not barcode:
        return False, "Barcode is required"
    if not name:
        return False, "Product name is required"

    selling_price = parse_float(selling_price, -1)
    if selling_price <= 0:
        return False, "Selling price must be greater than 0"

    cost_price = parse_float(cost_price, 0)
    if cost_price < 0:
        return False, "Cost price cannot be negative"

    resolved_wholesale = parse_float(wholesale_price, selling_price)
    if resolved_wholesale <= 0:
        resolved_wholesale = selling_price

    resolved_sale_price = None if sale_price in (None, "") else parse_float(sale_price, -1)
    if normalize_bool(sale_enabled, False) and (resolved_sale_price is None or resolved_sale_price <= 0):
        return False, "Active sale price must be greater than 0"

    opening_stock = parse_int(opening_stock, 0)
    min_stock_level = parse_int(min_stock_level, 0)
    if opening_stock < 0:
        return False, "Opening stock cannot be negative"
    if min_stock_level < 0:
        return False, "Minimum stock level cannot be negative"

    existing = get_product_row(cursor, barcode)
    if existing:
        previous_stock = parse_int(existing["stock"], 0)
        cursor.execute(
            f"""
            UPDATE products
            SET name = ?,
                category = ?,
                quantity_type = ?,
                unit_label = ?,
                price = ?,
                cost_price = ?,
                selling_price = ?,
                wholesale_price = ?,
                sale_price = ?,
                sale_enabled = ?,
                stock = ?,
                min_stock_level = ?,
                is_active = 1,
                updated_at = {now_sql()},
                last_price_updated_at = {now_sql()}
            WHERE barcode = ?
            """,
            (
                name,
                category,
                quantity_type,
                unit_label,
                selling_price,
                cost_price,
                selling_price,
                resolved_wholesale,
                resolved_sale_price,
                1 if normalize_bool(sale_enabled, False) else 0,
                opening_stock,
                min_stock_level,
                barcode,
            ),
        )
    else:
        cursor.execute(
            f"""
            INSERT INTO products (
                barcode,
                name,
                category,
                quantity_type,
                unit_label,
                price,
                cost_price,
                selling_price,
                wholesale_price,
                sale_price,
                sale_enabled,
                stock,
                min_stock_level,
                is_active,
                updated_at,
                last_price_updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, {now_sql()}, {now_sql()})
            """,
            (
                barcode,
                name,
                category,
                quantity_type,
                unit_label,
                selling_price,
                cost_price,
                selling_price,
                resolved_wholesale,
                resolved_sale_price,
                1 if normalize_bool(sale_enabled, False) else 0,
                opening_stock,
                min_stock_level,
            ),
        )

    movement_type = "product_updated" if existing else "product_created"
    reference_type = "product_update" if existing else "product_create"
    main_reason = reason or ("Product updated" if existing else "Product added to inventory")
    main_history = log_inventory_history(
        cursor,
        barcode=barcode,
        movement_type=movement_type,
        quantity=0,
        reason=main_reason,
        reference_type=reference_type,
        reference_id=None,
    )

    if mirror_to_pos:
        mirror_inventory_movement_to_pos(
            barcode=barcode,
            product_name=name,
            action_type=movement_type,
            stock_before=previous_stock if existing else None,
            stock_after=opening_stock if existing else opening_stock,
            reason=main_reason,
            reference_id=main_history["id"],
            reference_type="backend_history",
            performed_by="Admin App",
            created_at=main_history["created_at"],
        )

    if not existing and opening_stock > 0:
        stock_history = log_inventory_history(
            cursor,
            barcode=barcode,
            movement_type="stock_receive",
            quantity=opening_stock,
            reason="Opening stock added during product creation",
            reference_type="product_create",
            reference_id=None,
        )
        if mirror_to_pos:
            mirror_inventory_movement_to_pos(
                barcode=barcode,
                product_name=name,
                action_type="stock_receive",
                quantity_change=opening_stock,
                stock_before=0,
                stock_after=opening_stock,
                reason="Opening stock added during product creation",
                reference_id=stock_history["id"],
                reference_type="backend_history",
                performed_by="Admin App",
                created_at=stock_history["created_at"],
            )
    elif existing and previous_stock != opening_stock:
        stock_history = log_inventory_history(
            cursor,
            barcode=barcode,
            movement_type="product_updated",
            quantity=opening_stock - previous_stock,
            reason="Product stock replaced during update",
            reference_type="product_update",
            reference_id=None,
        )
        if mirror_to_pos:
            mirror_inventory_movement_to_pos(
                barcode=barcode,
                product_name=name,
                action_type="stock_adjust_set",
                quantity_change=opening_stock - previous_stock,
                stock_before=previous_stock,
                stock_after=opening_stock,
                reason="Product stock replaced during update",
                reference_id=stock_history["id"],
                reference_type="backend_history",
                performed_by="Admin App",
                created_at=stock_history["created_at"],
            )

    return True, "success"


def delete_product(cursor, barcode, reason="", mirror_to_pos=True):
    barcode = str(barcode or "").strip()
    if not barcode:
        return False, "Barcode is required"

    row = get_product_row(cursor, barcode)
    if not row:
        return False, "Product not found"

    product_name = str(row["name"] or "Unknown product")
    stock_before = parse_int(row["stock"], 0)
    cursor.execute("DELETE FROM products WHERE barcode = ?", (barcode,))

    note = reason or "Product removed from inventory"
    history_entry = log_inventory_history(
        cursor,
        barcode=barcode,
        movement_type="product_deleted",
        quantity=0,
        reason=note,
        reference_type="product_delete",
        reference_id=None,
    )

    if mirror_to_pos:
        mirror_inventory_movement_to_pos(
            barcode=barcode,
            product_name=product_name,
            action_type="product_deleted",
            stock_before=stock_before,
            stock_after=0,
            reason=note,
            reference_id=history_entry["id"],
            reference_type="backend_history",
            performed_by="Admin App",
            created_at=history_entry["created_at"],
        )
    return True, "success"


def bulk_delete_products(cursor, barcodes, reason="", mirror_to_pos=True):
    deleted = 0
    for raw_barcode in barcodes or []:
        barcode = str(raw_barcode or "").strip()
        if not barcode:
            continue
        ok, _ = delete_product(cursor, barcode, reason=reason, mirror_to_pos=mirror_to_pos)
        if ok:
            deleted += 1
    return True, deleted


def fetch_products(cursor):
    rows = cursor.execute(
        """
        SELECT
            id,
            barcode,
            name,
            COALESCE(category, 'General') AS category,
            CASE
                WHEN LOWER(COALESCE(quantity_type, '')) = 'weight' THEN 'weight'
                ELSE 'unit'
            END AS quantity_type,
            CASE
                WHEN TRIM(COALESCE(unit_label, '')) != '' THEN TRIM(unit_label)
                WHEN LOWER(COALESCE(quantity_type, 'unit')) = 'weight' THEN 'kg'
                ELSE 'pcs'
            END AS unit_label,
            COALESCE(cost_price, 0) AS cost_price,
            COALESCE(selling_price, price, 0) AS selling_price,
            COALESCE(price, selling_price, 0) AS price,
            CASE
                WHEN COALESCE(wholesale_price, 0) <= 0 THEN COALESCE(selling_price, price, 0)
                ELSE wholesale_price
            END AS wholesale_price,
            sale_price,
            COALESCE(sale_enabled, CASE WHEN sale_price IS NOT NULL THEN 1 ELSE 0 END) AS sale_enabled,
            COALESCE(stock, 0) AS stock,
            COALESCE(min_stock_level, 0) AS min_stock_level,
            COALESCE(is_active, 1) AS is_active,
            updated_at,
            last_price_updated_at
        FROM products
        ORDER BY name COLLATE NOCASE ASC
        """
    ).fetchall()
    return [dict(r) for r in rows]



def _safe_json_loads(raw_value):
    try:
        return json.loads(raw_value or "[]")
    except Exception:
        return []


def _extract_item_quantity(item):
    return round_quantity(item.get("quantity", 0))


def _extract_item_price(item):
    direct_keys = [
        "selected_price",
        "unit_price",
        "price",
        "effective_price",
        "sale_price",
    ]
    for key in direct_keys:
        value = parse_float(item.get(key), -1)
        if value >= 0:
            return value

    product = item.get("product", {}) or {}
    for key in ["selling_price", "price", "wholesale_price", "sale_price"]:
        value = parse_float(product.get(key), -1)
        if value >= 0:
            return value

    return 0.0


def _extract_item_line_total(item):
    if item.get("line_total") is None:
        return None
    return parse_float(item.get("line_total"), 0.0)


def _extract_item_base_line_total(item):
    if item.get("base_line_total") is None:
        return None
    return parse_float(item.get("base_line_total"), 0.0)


def _extract_item_discount_amount(item):
    if item.get("item_discount_amount") is None:
        return None
    return parse_float(item.get("item_discount_amount"), 0.0)


def _extract_item_cost_snapshot(item):
    for key in ["cost_price_snapshot", "unit_cost", "cost_price"]:
        if item.get(key) is not None:
            return parse_float(item.get(key), 0.0)
    product = item.get("product", {}) or {}
    return parse_float(product.get("cost_price"), 0.0)


def _item_bool(value, default=False):
    return 1 if normalize_bool(value, default) else 0


def insert_sale_item_snapshots(cursor, sale_id, items, created_at):
    create_sale_items_table(cursor)
    cursor.execute("DELETE FROM sale_items WHERE sale_id = ?", (sale_id,))

    for item in items:
        product = item.get("product", {}) or {}
        barcode = _extract_item_barcode(item)
        product_name = _extract_item_name(item)
        quantity = max(_extract_item_quantity(item), 0)
        unit_price = parse_float(
            item.get("unit_price_used", item.get("unit_price", item.get("price"))),
            _extract_item_price(item),
        )
        system_unit_price = parse_float(item.get("system_unit_price"), unit_price)
        marked_price = parse_float(product.get("selling_price", product.get("price")), unit_price)
        base_line_total = parse_float(
            item.get("base_line_total"),
            unit_price * quantity,
        )
        item_discount = parse_float(item.get("item_discount_amount"), 0.0)
        line_total = parse_float(
            item.get("line_total"),
            max(0.0, base_line_total - item_discount),
        )
        price_override_type = str(item.get("price_override_type") or "none").strip().lower()
        if price_override_type not in {"none", "manual", "old_label"}:
            price_override_type = "none"
        customer_pricing_type = str(item.get("customer_pricing_type") or "none").strip().lower()
        if customer_pricing_type not in {
            "none",
            "customer_product_price",
            "customer_default_price_type",
            "customer_default_discount",
        }:
            customer_pricing_type = "none"

        cursor.execute(
            """
            INSERT INTO sale_items (
                sale_id, barcode, product_name, unit_price, marked_price,
                price_category_used, system_unit_price, price_override_type,
                price_override_reason, price_override_original_price,
                price_override_difference, price_history_id,
                price_override_approved_by, cost_price_snapshot, quantity,
                base_line_total, item_discount_type, item_discount_value,
                explicit_item_discount_amount, cart_discount_amount,
                item_discount_amount, line_total, customer_pricing_applied,
                customer_pricing_type, customer_pricing_rule_id,
                customer_pricing_original_price, customer_pricing_final_price,
                customer_pricing_discount_amount, customer_pricing_note, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                sale_id,
                barcode,
                product_name,
                unit_price,
                marked_price,
                normalize_price_type(item.get("price_type_used") or item.get("price_category_used")),
                system_unit_price,
                price_override_type,
                clean_optional_text(item.get("price_override_reason")) or "",
                parse_float(item.get("price_override_original_price"), system_unit_price),
                parse_float(item.get("price_override_difference"), unit_price - system_unit_price),
                parse_int(item.get("price_history_id"), 0) or None,
                clean_optional_text(item.get("price_override_approved_by")),
                _extract_item_cost_snapshot(item),
                quantity,
                base_line_total,
                str(item.get("item_discount_type") or "none"),
                parse_float(item.get("item_discount_value"), 0.0),
                parse_float(item.get("explicit_item_discount_amount"), 0.0),
                parse_float(item.get("cart_discount_amount"), 0.0),
                item_discount,
                line_total,
                _item_bool(item.get("customer_pricing_applied"), False),
                customer_pricing_type,
                parse_int(item.get("customer_pricing_rule_id"), 0) or None,
                parse_float(item.get("customer_pricing_original_price"), 0.0),
                parse_float(item.get("customer_pricing_final_price"), 0.0),
                parse_float(item.get("customer_pricing_discount_amount"), 0.0),
                clean_optional_text(item.get("customer_pricing_note")),
                created_at,
            ),
        )


def _extract_item_sales_amount(item):
    line_total = _extract_item_line_total(item)
    if line_total is not None:
        return abs(line_total)
    base_line_total = _extract_item_base_line_total(item)
    item_discount = _extract_item_discount_amount(item)
    if base_line_total is not None:
        return max(0.0, abs(base_line_total) - abs(item_discount or 0.0))
    quantity = max(_extract_item_quantity(item), 0)
    unit_price = max(_extract_item_price(item), 0.0)
    return quantity * unit_price


def _extract_item_refund_amount(item):
    line_total = _extract_item_line_total(item)
    if line_total is not None:
        return abs(line_total)
    quantity = max(_extract_item_quantity(item), 0)
    unit_price = max(_extract_item_price(item), 0.0)
    return quantity * unit_price


def _extract_item_name(item):
    product = item.get("product", {}) or {}
    return str(product.get("name") or item.get("name") or "Unknown Item")


def _extract_item_barcode(item):
    product = item.get("product", {}) or {}
    return str(product.get("barcode") or item.get("barcode") or "")


def _extract_item_quantity_type(item):
    product = item.get("product", {}) or {}
    return normalize_quantity_type(product.get("quantity_type") or item.get("quantity_type"))


def _extract_item_unit_label(item):
    product = item.get("product", {}) or {}
    quantity_type = _extract_item_quantity_type(item)
    return normalize_unit_label(
        quantity_type,
        product.get("unit_label") or item.get("unit_label"),
    )


def _sales_rows_between(cursor, start_sql_expr, end_sql_expr):
    return cursor.execute(
        f"""
        SELECT total_amount, items, cashier_name, created_at
        FROM sales
        WHERE datetime(created_at) >= {start_sql_expr}
          AND datetime(created_at) < {end_sql_expr}
        ORDER BY datetime(created_at) ASC
        """
    ).fetchall()


def _build_owner_summary_from_rows(rows):
    today_sales = 0.0
    transaction_count = len(rows)
    items_sold = 0
    products = {}

    for row in rows:
        today_sales += parse_float(row["total_amount"], 0.0)
        items = _safe_json_loads(row["items"])

        for item in items:
            quantity = max(_extract_item_quantity(item), 0)
            price = max(_extract_item_price(item), 0.0)
            name = _extract_item_name(item)
            barcode = _extract_item_barcode(item)
            quantity_type = _extract_item_quantity_type(item)
            unit_label = _extract_item_unit_label(item)

            items_sold += quantity
            product_key = barcode or name

            if product_key not in products:
                products[product_key] = {
                    "barcode": barcode,
                    "product_name": name,
                    "quantity_type": quantity_type,
                    "unit_label": unit_label,
                    "quantity_sold": 0,
                    "total_sales": 0.0,
                }

            products[product_key]["quantity_sold"] += quantity
            products[product_key]["total_sales"] += quantity * price

    average_sale = today_sales / transaction_count if transaction_count > 0 else 0.0
    top_products = sorted(
        products.values(),
        key=lambda item: (item["total_sales"], item["quantity_sold"]),
        reverse=True,
    )[:3]

    return {
        "summary": {
            "today_sales": round(today_sales, 2),
            "transaction_count": transaction_count,
            "average_sale": round(average_sale, 2),
            "items_sold": items_sold,
        },
        "top_products": top_products,
    }


def _owner_trend(cursor, days=7):
    rows = cursor.execute(
        """
        SELECT
            DATE(created_at) AS sales_date,
            COALESCE(SUM(total_amount), 0) AS total_sales
        FROM sales
        WHERE DATE(created_at) >= DATE('now','localtime', ?)
          AND DATE(created_at) <= DATE('now','localtime')
        GROUP BY DATE(created_at)
        ORDER BY DATE(created_at) ASC
        """,
        (f"-{days - 1} day",),
    ).fetchall()

    raw_map = {row["sales_date"]: parse_float(row["total_sales"], 0.0) for row in rows}
    date_rows = cursor.execute(
        """
        WITH RECURSIVE dates(day, idx) AS (
            SELECT DATE('now','localtime', ?) AS day, 0
            UNION ALL
            SELECT DATE(day, '+1 day'), idx + 1
            FROM dates
            WHERE idx < ?
        )
        SELECT day FROM dates
        """,
        (f"-{days - 1} day", days - 1),
    ).fetchall()

    trend = []
    for row in date_rows:
        day = row["day"]
        trend.append(
            {
                "date": day,
                "label": day[5:].replace("-", "/"),
                "total_sales": round(raw_map.get(day, 0.0), 2),
            }
        )
    return trend


def _top_sellers_last_days(cursor, days=30, limit=10):
    rows = _sales_rows_between(
        cursor,
        f"datetime('now','localtime','-{days - 1} day','start of day')",
        "datetime('now','localtime','+1 day','start of day')",
    )

    by_product = {}
    for row in rows:
        items = _safe_json_loads(row["items"])
        for item in items:
            barcode = _extract_item_barcode(item)
            name = _extract_item_name(item)
            quantity = max(_extract_item_quantity(item), 0)
            price = max(_extract_item_price(item), 0.0)
            key = barcode or name
            if key not in by_product:
                by_product[key] = {
                    "barcode": barcode,
                    "product_name": name,
                    "quantity_sold": 0,
                    "total_sales": 0.0,
                }
            by_product[key]["quantity_sold"] += quantity
            by_product[key]["total_sales"] += quantity * price

    return sorted(
        by_product.values(),
        key=lambda item: (item["quantity_sold"], item["total_sales"]),
        reverse=True,
    )[:limit]


def _build_owner_alerts(cursor):
    alerts = []

    def stock_text(product, value):
        return format_stock_with_unit(
            product.get("quantity_type"),
            product.get("unit_label"),
            value,
        )

    products = fetch_products(cursor)
    quantity_epsilon = 0.000001
    out_of_stock = [
        p for p in products if parse_float(p.get("stock", 0), 0.0) <= quantity_epsilon
    ]
    low_stock = [
        p
        for p in products
        if parse_float(p.get("stock", 0), 0.0) > quantity_epsilon
        and parse_float(p.get("stock", 0), 0.0)
        <= (parse_float(p.get("min_stock_level", 0), 0.0) or 10.0)
    ]

    out_of_stock = sorted(out_of_stock, key=lambda item: item["name"])
    low_stock = sorted(low_stock, key=lambda item: parse_float(item.get("stock", 0), 0.0))

    for product in out_of_stock[:6]:
        supplier_contact = _latest_supplier_contact_for_barcode(
            cursor,
            str(product["barcode"]),
        )
        alerts.append(
            {
                "type": "out_of_stock",
                "severity": "critical",
                "title": f"{product['name']} is out of stock",
                "subtitle": f"Barcode {product['barcode']} - stock {stock_text(product, 0)}",
                "barcode": product["barcode"],
                **supplier_contact,
            }
        )

    top_sellers = _top_sellers_last_days(cursor, days=30, limit=20)
    product_by_barcode = {str(p["barcode"]): p for p in products if p.get("barcode")}
    best_seller_risk = []
    for seller in top_sellers:
        barcode = str(seller.get("barcode") or "")
        if not barcode or barcode not in product_by_barcode:
            continue
        product = product_by_barcode[barcode]
        stock = parse_float(product.get("stock", 0), 0.0)
        min_stock = parse_float(product.get("min_stock_level", 0), 0.0) or 10.0
        if stock > quantity_epsilon and stock <= min_stock:
            best_seller_risk.append((seller, product))

    for seller, product in best_seller_risk[:4]:
        supplier_contact = _latest_supplier_contact_for_barcode(
            cursor,
            str(product["barcode"]),
        )
        alerts.append(
            {
                "type": "best_seller_low_stock",
                "severity": "warning",
                "title": f"Best seller low in stock: {product['name']}",
                "subtitle": (
                    f"Sold {format_quantity(seller['quantity_sold'])} recently - "
                    f"stock {stock_text(product, product.get('stock', 0))}"
                ),
                "barcode": product["barcode"],
                **supplier_contact,
            }
        )

    already_added = {alert.get("barcode") for alert in alerts if alert.get("barcode")}
    for product in low_stock[:6]:
        if product["barcode"] in already_added:
            continue
        supplier_contact = _latest_supplier_contact_for_barcode(
            cursor,
            str(product["barcode"]),
        )
        alerts.append(
            {
                "type": "low_stock",
                "severity": "warning",
                "title": f"{product['name']} is low in stock",
                "subtitle": f"Barcode {product['barcode']} - stock {stock_text(product, product.get('stock', 0))}",
                "barcode": product["barcode"],
                **supplier_contact,
            }
        )

    today_rows = _sales_rows_between(
        cursor,
        "datetime('now','localtime','start of day')",
        "datetime('now','localtime','+1 day','start of day')",
    )
    yesterday_rows = _sales_rows_between(
        cursor,
        "datetime('now','localtime','-1 day','start of day')",
        "datetime('now','localtime','start of day')",
    )

    today_total = sum(parse_float(row["total_amount"], 0.0) for row in today_rows)
    yesterday_total = sum(parse_float(row["total_amount"], 0.0) for row in yesterday_rows)

    if today_total <= 0:
        alerts.insert(
            0,
            {
                "type": "weak_sales",
                "severity": "warning",
                "title": "No sales recorded today",
                "subtitle": "Check store activity and cashier flow.",
            },
        )
    elif yesterday_total > 0 and today_total < yesterday_total * 0.6:
        alerts.append(
            {
                "type": "weak_sales",
                "severity": "warning",
                "title": "Sales are weaker than yesterday",
                "subtitle": f"Today Rs.{today_total:.2f} vs yesterday Rs.{yesterday_total:.2f}",
            }
        )

    return alerts


def _latest_supplier_contact_for_barcode(cursor, barcode):
    if not barcode:
        return {}

    mapped = cursor.execute(
        """
        SELECT m.supplier_id AS id, s.name, s.phone
        FROM supplier_product_mappings m
        LEFT JOIN suppliers s ON s.id = m.supplier_id
        WHERE m.barcode = ?
          AND m.supplier_id > 0
        LIMIT 1
        """,
        (barcode,),
    ).fetchone()

    if mapped:
        mapped_name = str(mapped["name"] or "").strip()
        mapped_phone = str(mapped["phone"] or "").strip()
        if mapped_name or mapped_phone:
            return {
                "supplier_id": parse_int(mapped["id"], 0),
                "supplier_name": mapped_name,
                "supplier_phone": mapped_phone,
            }

    row = cursor.execute(
        """
        SELECT s.id, s.name, s.phone
        FROM stock_receipts sr
        JOIN suppliers s ON s.id = sr.supplier_id
        WHERE sr.barcode = ?
          AND sr.supplier_id IS NOT NULL
          AND sr.supplier_id > 0
        ORDER BY datetime(sr.created_at) DESC, sr.id DESC
        LIMIT 1
        """,
        (barcode,),
    ).fetchone()

    if row:
        row_name = str(row["name"] or "").strip()
        row_phone = str(row["phone"] or "").strip()
        if row_name or row_phone:
            return {
                "supplier_id": parse_int(row["id"], 0),
                "supplier_name": row_name,
                "supplier_phone": row_phone,
            }

    if os.path.exists(POS_DB_PATH):
        pos_conn = None
        try:
            pos_conn = get_pos_db()
            pos_cursor = pos_conn.cursor()

            mapped = pos_cursor.execute(
                """
                SELECT m.supplier_id AS id, COALESCE(NULLIF(TRIM(s.name), ''), m.supplier_name) AS name, s.phone
                FROM supplier_product_mappings m
                LEFT JOIN suppliers s ON s.id = m.supplier_id
                WHERE m.barcode = ?
                  AND m.supplier_id > 0
                ORDER BY m.is_preferred DESC, m.id ASC
                LIMIT 1
                """,
                (barcode,),
            ).fetchone()

            if mapped:
                mapped_name = str(mapped["name"] or "").strip()
                mapped_phone = str(mapped["phone"] or "").strip()
                if mapped_name or mapped_phone:
                    return {
                        "supplier_id": parse_int(mapped["id"], 0),
                        "supplier_name": mapped_name,
                        "supplier_phone": mapped_phone,
                    }

            row = pos_cursor.execute(
                """
                SELECT sr.supplier_id AS id, COALESCE(NULLIF(TRIM(s.name), ''), sr.supplier_name) AS name, s.phone
                FROM stock_receipts sr
                LEFT JOIN suppliers s ON s.id = sr.supplier_id
                WHERE sr.barcode = ?
                  AND sr.supplier_id IS NOT NULL
                  AND sr.supplier_id > 0
                ORDER BY datetime(sr.created_at) DESC, sr.id DESC
                LIMIT 1
                """,
                (barcode,),
            ).fetchone()

            if row:
                row_name = str(row["name"] or "").strip()
                row_phone = str(row["phone"] or "").strip()
                if row_name or row_phone:
                    return {
                        "supplier_id": parse_int(row["id"], 0),
                        "supplier_name": row_name,
                        "supplier_phone": row_phone,
                    }
        except Exception as exc:
            print(f"Supplier contact lookup failed for {barcode}: {exc}")
        finally:
            if pos_conn is not None:
                try:
                    pos_conn.close()
                except Exception:
                    pass

    return {}


def _upsert_supplier_product_mapping(cursor, barcode, supplier_id):
    if not barcode or parse_int(supplier_id, 0) <= 0:
        return

    cursor.execute(
        f"""
        INSERT INTO supplier_product_mappings (
            barcode,
            supplier_id,
            updated_at
        )
        VALUES (?, ?, {now_sql()})
        ON CONFLICT(barcode) DO UPDATE SET
            supplier_id = excluded.supplier_id,
            updated_at = excluded.updated_at
        """,
        (barcode, parse_int(supplier_id, 0)),
    )


def _safe_iso_date(raw_value):
    try:
        return datetime.fromisoformat(str(raw_value)[:10]).date()
    except Exception:
        return None


def _resolve_sales_report_window(params):
    today = datetime.now().date()
    range_key = str(params.get("range", ["today"])[0] or "today").strip().lower()

    if range_key in {"7d", "last7", "last_7", "weekly"}:
        start = today - timedelta(days=6)
        end = today
        label = "Last 7 Days"
    elif range_key in {"30d", "last30", "last_30", "monthly"}:
        start = today - timedelta(days=29)
        end = today
        label = "Last 30 Days"
    elif range_key in {"specific", "date"}:
        picked = _safe_iso_date(params.get("date", [""])[0]) or today
        start = picked
        end = picked
        label = picked.isoformat()
    elif range_key in {"custom", "range_custom", "date_range"}:
        start = _safe_iso_date(params.get("start_date", [""])[0]) or today
        end = _safe_iso_date(params.get("end_date", [""])[0]) or today
        if end < start:
            start, end = end, start
        label = f"{start.isoformat()} to {end.isoformat()}"
    else:
        start = today
        end = today
        label = "Today"

    return {
        "range_key": range_key,
        "label": label,
        "start_date": start,
        "end_date": end,
        "start_sql": f"{start.isoformat()} 00:00:00",
        "end_sql": f"{(end + timedelta(days=1)).isoformat()} 00:00:00",
    }


def _sales_rows_between_values(cursor, start_sql_value, end_sql_value):
    return cursor.execute(
        """
        SELECT
            id,
            COALESCE(total_amount, 0) AS total_amount,
            COALESCE(subtotal_amount, 0) AS subtotal_amount,
            COALESCE(discount_amount, 0) AS discount_amount,
            COALESCE(payment_method, '') AS payment_method,
            COALESCE(transaction_type, 'sale') AS transaction_type,
            COALESCE(items_count, 0) AS items_count,
            COALESCE(gross_profit, 0) AS gross_profit,
            cashier_name,
            items,
            created_at
        FROM sales
        WHERE datetime(created_at) >= ?
          AND datetime(created_at) < ?
        ORDER BY datetime(created_at) ASC, id ASC
        """,
        (start_sql_value, end_sql_value),
    ).fetchall()


def _extract_sale_hour(created_at_value):
    raw = str(created_at_value or "").strip()
    if len(raw) >= 13:
        try:
            hour = int(raw[11:13])
            if 0 <= hour <= 23:
                return hour
        except Exception:
            pass

    try:
        normalized = raw.replace("Z", "+00:00")
        hour = datetime.fromisoformat(normalized).hour
        if 0 <= hour <= 23:
            return hour
    except Exception:
        pass

    return 0


def _build_owner_sales_report(cursor, params):
    window = _resolve_sales_report_window(params)
    rows = _sales_rows_between_values(cursor, window["start_sql"], window["end_sql"])
    products = fetch_products(cursor)
    product_by_barcode = {str(p.get("barcode") or ""): p for p in products}
    hourly_requested = any(
        str(params.get(key, [""])[0] or "").strip().lower() == "hourly"
        for key in ("granularity", "view", "breakdown")
    )

    gross_sales = 0.0
    sales_net = 0.0
    discounts = 0.0
    refunds = 0.0
    cash_sales = 0.0
    card_sales = 0.0
    legacy_untyped_payment_sales = 0.0
    items_sold = 0
    sale_count = 0
    refund_count = 0
    gross_profit = 0.0
    by_cashier = {}
    by_product = {}
    day_buckets = {}

    span_days = (window["end_date"] - window["start_date"]).days + 1
    include_hourly_trend = span_days == 1 or hourly_requested
    hour_buckets = {}

    for row in rows:
        transaction_type = str(row["transaction_type"] or "sale").strip().lower()
        total_amount = abs(parse_float(row["total_amount"], 0.0))
        subtotal_amount = abs(parse_float(row["subtotal_amount"], 0.0))
        discount_amount = abs(parse_float(row["discount_amount"], 0.0))
        payment_method = str(row["payment_method"] or "").strip().lower()
        created_at = str(row["created_at"] or "")
        sale_day = created_at[:10]
        sale_hour = _extract_sale_hour(created_at)
        cashier_name = str(row["cashier_name"] or "Unknown")
        items = _safe_json_loads(row["items"])

        day_bucket = day_buckets.setdefault(
            sale_day,
            {
                "date": sale_day,
                "label": sale_day[5:].replace('-', '/'),
                "gross_sales": 0.0,
                "discounts": 0.0,
                "net_sales": 0.0,
                "refund_total": 0.0,
                "net_after_refunds": 0.0,
                "gross_profit": 0.0,
                "sale_count": 0,
                "refund_count": 0,
                "items_sold": 0,
            },
        )
        hour_bucket = hour_buckets.setdefault(
            sale_hour,
            {
                "hour": sale_hour,
                "label": f"{sale_hour:02d}:00",
                "gross_sales": 0.0,
                "discounts": 0.0,
                "net_sales": 0.0,
                "refund_total": 0.0,
                "net_after_refunds": 0.0,
                "gross_profit": 0.0,
                "sale_count": 0,
                "refund_count": 0,
                "transaction_count": 0,
                "items_sold": 0,
            },
        )
        cashier_bucket = by_cashier.setdefault(
            cashier_name,
            {
                "cashier_name": cashier_name,
                "sale_count": 0,
                "refund_count": 0,
                "transaction_count": 0,
                "items_sold": 0,
                "gross_sales": 0.0,
                "discounts": 0.0,
                "net_sales": 0.0,
                "refund_total": 0.0,
                "net_after_refunds": 0.0,
                "gross_profit": 0.0,
            },
        )

        row_profit = 0.0
        if transaction_type == "refund":
            refund_count += 1
            refunds += total_amount
            day_bucket["refund_count"] += 1
            day_bucket["refund_total"] += total_amount
            hour_bucket["refund_count"] += 1
            hour_bucket["transaction_count"] += 1
            hour_bucket["refund_total"] += total_amount
            cashier_bucket["refund_count"] += 1
            cashier_bucket["transaction_count"] += 1
            cashier_bucket["refund_total"] += total_amount
        else:
            sale_count += 1
            effective_subtotal = subtotal_amount if subtotal_amount > 0 else total_amount + discount_amount
            gross_sales += effective_subtotal
            discounts += discount_amount
            sales_net += total_amount
            day_bucket["sale_count"] += 1
            day_bucket["gross_sales"] += effective_subtotal
            day_bucket["discounts"] += discount_amount
            day_bucket["net_sales"] += total_amount
            hour_bucket["sale_count"] += 1
            hour_bucket["transaction_count"] += 1
            hour_bucket["gross_sales"] += effective_subtotal
            hour_bucket["discounts"] += discount_amount
            hour_bucket["net_sales"] += total_amount
            cashier_bucket["sale_count"] += 1
            cashier_bucket["transaction_count"] += 1
            cashier_bucket["gross_sales"] += effective_subtotal
            cashier_bucket["discounts"] += discount_amount
            cashier_bucket["net_sales"] += total_amount
            if payment_method == "card":
                card_sales += total_amount
            elif payment_method == "cash":
                cash_sales += total_amount
            else:
                cash_sales += total_amount
                legacy_untyped_payment_sales += total_amount

        for item in items:
            quantity = max(_extract_item_quantity(item), 0)
            if quantity <= 0:
                continue
            barcode = _extract_item_barcode(item)
            name = _extract_item_name(item)
            quantity_type = _extract_item_quantity_type(item)
            unit_label = _extract_item_unit_label(item)
            unit_cost = _extract_item_cost_snapshot(item)
            if unit_cost <= 0:
                unit_cost = parse_float(product_by_barcode.get(barcode, {}).get("cost_price"), 0.0)
            product_key = barcode or name
            bucket = by_product.setdefault(
                product_key,
                {
                    "barcode": barcode,
                    "product_name": name,
                    "quantity_type": quantity_type,
                    "unit_label": unit_label,
                    "quantity_sold": 0,
                    "refunded_quantity": 0,
                    "net_quantity_sold": 0,
                    "sales_amount": 0.0,
                    "refund_amount": 0.0,
                    "net_sales_after_refunds": 0.0,
                    "net_cost_amount": 0.0,
                    "estimated_profit": 0.0,
                },
            )
            if transaction_type == "refund":
                amount = _extract_item_refund_amount(item)
                cost_total = unit_cost * quantity
                bucket["refunded_quantity"] += quantity
                bucket["refund_amount"] += amount
                bucket["net_sales_after_refunds"] -= amount
                bucket["net_cost_amount"] -= cost_total
                bucket["estimated_profit"] -= (amount - cost_total)
                row_profit += (amount - cost_total)
            else:
                amount = _extract_item_sales_amount(item)
                cost_total = unit_cost * quantity
                items_sold += quantity
                day_bucket["items_sold"] += quantity
                hour_bucket["items_sold"] += quantity
                cashier_bucket["items_sold"] += quantity
                bucket["quantity_sold"] += quantity
                bucket["sales_amount"] += amount
                bucket["net_sales_after_refunds"] += amount
                bucket["net_cost_amount"] += cost_total
                bucket["estimated_profit"] += (amount - cost_total)
                row_profit += (amount - cost_total)

        if transaction_type == "refund":
            gross_profit -= row_profit
            day_bucket["gross_profit"] -= row_profit
            hour_bucket["gross_profit"] -= row_profit
            cashier_bucket["gross_profit"] -= row_profit
        else:
            gross_profit += row_profit
            day_bucket["gross_profit"] += row_profit
            hour_bucket["gross_profit"] += row_profit
            cashier_bucket["gross_profit"] += row_profit

        day_bucket["net_after_refunds"] = day_bucket["net_sales"] - day_bucket["refund_total"]
        hour_bucket["net_after_refunds"] = hour_bucket["net_sales"] - hour_bucket["refund_total"]
        cashier_bucket["net_after_refunds"] = cashier_bucket["net_sales"] - cashier_bucket["refund_total"]

    average_sale = (sales_net / sale_count) if sale_count > 0 else 0.0
    net_after_refunds = sales_net - refunds
    margin_percent = (gross_profit / net_after_refunds * 100.0) if net_after_refunds > 0 else 0.0

    trend = []
    days_with_sales = 0
    for i in range(span_days):
        day = window["start_date"] + timedelta(days=i)
        key = day.isoformat()
        existing = day_buckets.get(key, {
            "date": key,
            "label": key[5:].replace('-', '/'),
            "gross_sales": 0.0,
            "discounts": 0.0,
            "net_sales": 0.0,
            "refund_total": 0.0,
            "net_after_refunds": 0.0,
            "gross_profit": 0.0,
            "sale_count": 0,
            "refund_count": 0,
            "items_sold": 0,
        })
        for k in ["gross_sales", "discounts", "net_sales", "refund_total", "net_after_refunds", "gross_profit"]:
            existing[k] = round(parse_float(existing[k], 0.0), 2)
        if existing["sale_count"] or existing["refund_count"]:
            days_with_sales += 1
        trend.append(existing)

    hourly_trend = []
    if include_hourly_trend:
        for hour in range(24):
            existing = hour_buckets.get(
                hour,
                {
                    "hour": hour,
                    "label": f"{hour:02d}:00",
                    "gross_sales": 0.0,
                    "discounts": 0.0,
                    "net_sales": 0.0,
                    "refund_total": 0.0,
                    "net_after_refunds": 0.0,
                    "gross_profit": 0.0,
                    "sale_count": 0,
                    "refund_count": 0,
                    "transaction_count": 0,
                    "items_sold": 0,
                },
            )
            for k in [
                "gross_sales",
                "discounts",
                "net_sales",
                "refund_total",
                "net_after_refunds",
                "gross_profit",
            ]:
                existing[k] = round(parse_float(existing[k], 0.0), 2)
            hourly_trend.append(existing)

    cashier_summary = sorted(by_cashier.values(), key=lambda item: (item["net_after_refunds"], item["sale_count"]), reverse=True)
    for row in cashier_summary:
        sales_only = parse_int(row["sale_count"], 0)
        for k in ["gross_sales", "discounts", "net_sales", "refund_total", "net_after_refunds", "gross_profit"]:
            row[k] = round(parse_float(row[k], 0.0), 2)
        row["average_sale"] = round(parse_float(row["net_after_refunds"], 0.0) / sales_only, 2) if sales_only > 0 else 0.0

    top_products = sorted(by_product.values(), key=lambda item: (item["net_sales_after_refunds"], item["quantity_sold"] - item["refunded_quantity"]), reverse=True)[:8]
    for row in top_products:
        row["net_quantity_sold"] = round_quantity(parse_float(row["quantity_sold"], 0.0) - parse_float(row["refunded_quantity"], 0.0))
        for k in ["sales_amount", "refund_amount", "net_sales_after_refunds", "net_cost_amount", "estimated_profit"]:
            row[k] = round(parse_float(row[k], 0.0), 2)
        sales_val = parse_float(row["net_sales_after_refunds"], 0.0)
        profit_val = parse_float(row["estimated_profit"], 0.0)
        row["margin_percent"] = round((profit_val / sales_val * 100.0), 1) if sales_val > 0 else 0.0

    sold_map = {str(item.get("barcode") or item.get("product_name") or ""): item for item in by_product.values()}
    slow_movers = []
    for product in products:
        stock = round_quantity(product.get("stock", 0))
        if stock <= 0:
            continue
        key = str(product.get("barcode") or product.get("name") or "")
        sold = sold_map.get(key, {})
        qty = max(round_quantity(sold.get("net_quantity_sold", sold.get("quantity_sold", 0))), 0.0)
        slow_movers.append({
            "barcode": product.get("barcode"),
            "product_name": product.get("name"),
            "quantity_sold": qty,
            "stock": stock,
            "stock_value": round(stock * parse_float(product.get("cost_price"), 0.0), 2),
        })
    slow_movers = sorted(slow_movers, key=lambda item: (item["quantity_sold"], -item["stock_value"]))[:8]

    return {
        "window": {
            "range_key": window["range_key"],
            "label": window["label"],
            "start_date": window["start_date"].isoformat(),
            "end_date": window["end_date"].isoformat(),
            "days_in_window": span_days,
            "days_with_sales": days_with_sales,
        },
        "summary": {
            "gross_sales": round(gross_sales, 2),
            "net_sales": round(sales_net, 2),
            "net_after_refunds": round(net_after_refunds, 2),
            "discounts": round(discounts, 2),
            "refunds": round(refunds, 2),
            "refund_count": refund_count,
            "cash_sales": round(cash_sales, 2),
            "card_sales": round(card_sales, 2),
            "legacy_untyped_payment_sales": round(legacy_untyped_payment_sales, 2),
            "payment_data_complete": legacy_untyped_payment_sales <= 0.0,
            "sale_count": sale_count,
            "transaction_count": sale_count + refund_count,
            "items_sold": items_sold,
            "average_sale": round(average_sale, 2),
            "gross_profit": round(gross_profit, 2),
            "profit": round(gross_profit, 2),
            "margin_percent": round(margin_percent, 1),
        },
        "trend": trend,
        "hourly_trend": hourly_trend,
        "cashier_summary": cashier_summary,
        "top_products": top_products,
        "slow_movers": slow_movers,
    }





def create_business_info_table(cursor):
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS business_info (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            store_name TEXT NOT NULL,
            branch_name TEXT,
            phone_number TEXT,
            email TEXT,
            address TEXT,
            business_hours TEXT,
            currency_code TEXT NOT NULL DEFAULT 'LKR',
            business_note TEXT,
            updated_at TEXT NOT NULL
        )
        """
    )


def seed_business_info_if_needed(cursor):
    create_business_info_table(cursor)
    row = cursor.execute('SELECT id FROM business_info WHERE id = 1 LIMIT 1').fetchone()
    if row:
        return
    now = datetime.now().astimezone().isoformat()
    cursor.execute(
        """
        INSERT INTO business_info (
            id, store_name, branch_name, phone_number, email, address,
            business_hours, currency_code, business_note, updated_at
        )
        VALUES (1, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            'Food City',
            'Main Branch',
            '',
            '',
            '',
            '8:00 AM - 10:00 PM',
            'LKR',
            '',
            now,
        ),
    )


def get_business_info(cursor):
    create_business_info_table(cursor)
    seed_business_info_if_needed(cursor)
    row = cursor.execute(
        """
        SELECT id, store_name, branch_name, phone_number, email, address,
               business_hours, currency_code, business_note, updated_at
        FROM business_info
        WHERE id = 1
        LIMIT 1
        """
    ).fetchone()
    return dict(row) if row else {
        'store_name': 'Food City',
        'branch_name': 'Main Branch',
        'phone_number': '',
        'email': '',
        'address': '',
        'business_hours': '8:00 AM - 10:00 PM',
        'currency_code': 'LKR',
        'business_note': '',
        'updated_at': datetime.now().astimezone().isoformat(),
    }


def update_business_info(cursor, body):
    create_business_info_table(cursor)
    seed_business_info_if_needed(cursor)

    store_name = str(body.get('store_name', '') or '').strip()
    if not store_name:
        return False, 'Store name is required'

    branch_name = str(body.get('branch_name', '') or '').strip()
    phone_number = str(body.get('phone_number', '') or '').strip()
    email = str(body.get('email', '') or '').strip()
    address = str(body.get('address', '') or '').strip()
    business_hours = str(body.get('business_hours', '') or '').strip()
    currency_code = str(body.get('currency_code', 'LKR') or 'LKR').strip().upper() or 'LKR'
    business_note = str(body.get('business_note', '') or '').strip()
    now = datetime.now().astimezone().isoformat()

    cursor.execute(
        """
        UPDATE business_info
        SET store_name = ?,
            branch_name = ?,
            phone_number = ?,
            email = ?,
            address = ?,
            business_hours = ?,
            currency_code = ?,
            business_note = ?,
            updated_at = ?
        WHERE id = 1
        """,
        (
            store_name,
            branch_name,
            phone_number,
            email,
            address,
            business_hours,
            currency_code,
            business_note,
            now,
        ),
    )
    return True, 'success'


def _normalize_user_role(value):
    normalized = str(value or '').strip().lower()
    return 'manager' if normalized == 'manager' else 'cashier'


def _normalize_user_status_filter(value):
    normalized = str(value or '').strip().lower()
    if normalized == 'active':
        return 'active'
    if normalized == 'inactive':
        return 'inactive'
    return 'all'


def _normalize_user_log_filter(value):
    normalized = str(value or '').strip().lower()
    return normalized or 'all'


def create_user_tables(cursor):
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            role TEXT NOT NULL,
            pin TEXT UNIQUE NOT NULL,
            is_active INTEGER NOT NULL DEFAULT 1,
            has_full_access INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            last_login_at TEXT,
            created_by INTEGER,
            updated_by INTEGER
        )
        """
    )

    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS user_logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            actor_user_id INTEGER,
            actor_name TEXT NOT NULL,
            action_type TEXT NOT NULL,
            target_user_id INTEGER,
            target_user_name TEXT,
            description TEXT NOT NULL,
            created_at TEXT NOT NULL
        )
        """
    )


def insert_user_log(cursor, actor_user_id=None, actor_name='System', action_type='user_updated',
                    target_user_id=None, target_user_name=None, description='', created_at=None):
    cursor.execute(
        """
        INSERT INTO user_logs (
            actor_user_id,
            actor_name,
            action_type,
            target_user_id,
            target_user_name,
            description,
            created_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?)
        """,
        (
            actor_user_id,
            str(actor_name or 'System').strip() or 'System',
            str(action_type or 'user_updated').strip() or 'user_updated',
            target_user_id,
            str(target_user_name).strip() if target_user_name is not None else None,
            str(description or '').strip() or 'User activity recorded',
            created_at or datetime.now().astimezone().isoformat(),
        ),
    )


def seed_users_if_needed(cursor):
    count = cursor.execute("SELECT COUNT(*) AS count FROM users").fetchone()[0]
    if count > 0:
        return

    now = datetime.now().astimezone().isoformat()
    rows = [
        ('Pathum (Manager)', 'manager', '1234', 1, 0, now, now, None, None, None),
        ('Amal (Cashier)', 'cashier', '5555', 1, 0, now, now, None, None, None),
    ]
    cursor.executemany(
        """
        INSERT INTO users (
            name, role, pin, is_active, has_full_access,
            created_at, updated_at, last_login_at, created_by, updated_by
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        rows,
    )
    created = cursor.execute("SELECT id, name, role, created_at FROM users ORDER BY id ASC").fetchall()
    for row in created:
        insert_user_log(
            cursor,
            actor_user_id=None,
            actor_name='System',
            action_type='user_created',
            target_user_id=row['id'],
            target_user_name=row['name'],
            description=f"Created user {row['name']} ({'Manager' if row['role'] == 'manager' else 'Cashier'})",
            created_at=row['created_at'],
        )


def get_owner_user_summary(cursor):
    row = cursor.execute(
        """
        SELECT
            COUNT(*) AS total_users,
            COALESCE(SUM(CASE WHEN is_active = 1 THEN 1 ELSE 0 END), 0) AS active_users,
            COALESCE(SUM(CASE WHEN role = 'manager' THEN 1 ELSE 0 END), 0) AS managers,
            COALESCE(SUM(CASE WHEN role = 'cashier' THEN 1 ELSE 0 END), 0) AS cashiers
        FROM users
        """
    ).fetchone()
    return {
        'total_users': parse_int(row['total_users'], 0),
        'active_users': parse_int(row['active_users'], 0),
        'managers': parse_int(row['managers'], 0),
        'cashiers': parse_int(row['cashiers'], 0),
    }


def get_owner_users(cursor, params):
    search = str(params.get('search', [''])[0] or '').strip().lower()
    role = _normalize_user_role(params.get('role', ['all'])[0]) if str(params.get('role', ['all'])[0] or '').strip().lower() in {'manager','cashier'} else 'all'
    status = _normalize_user_status_filter(params.get('status', ['all'])[0])

    where_clauses = []
    where_args = []

    if role in {'manager', 'cashier'}:
        where_clauses.append('role = ?')
        where_args.append(role)
    if status == 'active':
        where_clauses.append('is_active = 1')
    elif status == 'inactive':
        where_clauses.append('is_active = 0')
    if search:
        where_clauses.append("(LOWER(name) LIKE ? OR LOWER(role) LIKE ? OR pin LIKE ?)")
        pattern = f"%{search}%"
        where_args.extend([pattern, pattern, pattern])

    query = """
        SELECT
            id,
            name,
            role,
            pin,
            COALESCE(is_active, 1) AS is_active,
            COALESCE(has_full_access, 0) AS has_full_access,
            created_at,
            updated_at,
            last_login_at
        FROM users
    """
    if where_clauses:
        query += " WHERE " + " AND ".join(where_clauses)
    query += " ORDER BY is_active DESC, role ASC, has_full_access DESC, name COLLATE NOCASE ASC"

    merged_rows = []
    conns = _get_user_db_connections(include_backend=True)
    try:
        for _name, conn, _path in conns:
            cur = conn.cursor()
            create_user_tables(cur)
            seed_users_if_needed(cur)
            conn.commit()
            rows = cur.execute(query, where_args).fetchall()
            merged_rows.extend([dict(row) for row in rows])
    finally:
        _close_user_db_connections(conns)

    merged_rows = _dedupe_user_rows(merged_rows)
    merged_rows.sort(key=lambda row: (-(parse_int(row.get('is_active'),1)), str(row.get('role') or ''), -parse_int(row.get('has_full_access'),0), str(row.get('name') or '').lower()))
    return merged_rows


def get_owner_activity_logs(cursor, params):
    search = str(params.get('search', [''])[0] or '').strip().lower()
    action_filter = _normalize_user_log_filter(params.get('filter', ['all'])[0])
    limit = parse_int(params.get('limit', ['50'])[0], 50)
    if limit <= 0:
        limit = 50
    if limit > 200:
        limit = 200

    where_clauses = []
    where_args = []

    if action_filter != 'all':
        if action_filter == 'logins':
            where_clauses.append("(action_type = 'login_success' OR action_type = 'login_failed' OR action_type = 'logout')")
        elif action_filter == 'user_changes':
            where_clauses.append("(action_type = 'user_created' OR action_type = 'user_updated' OR action_type = 'user_deactivated' OR action_type = 'user_reactivated' OR action_type = 'role_changed' OR action_type = 'full_access_granted' OR action_type = 'full_access_revoked')")
        elif action_filter == 'pin_changes':
            where_clauses.append("action_type = 'pin_reset'")
        elif action_filter == 'approvals':
            where_clauses.append("action_type = 'manager_approval'")
        else:
            where_clauses.append('action_type = ?')
            where_args.append(action_filter)

    if search:
        where_clauses.append("(LOWER(actor_name) LIKE ? OR LOWER(COALESCE(target_user_name, '')) LIKE ? OR LOWER(description) LIKE ?)")
        pattern = f"%{search}%"
        where_args.extend([pattern, pattern, pattern])

    query = """
        SELECT
            id,
            actor_user_id,
            actor_name,
            action_type,
            target_user_id,
            target_user_name,
            description,
            created_at
        FROM user_logs
    """
    if where_clauses:
        query += " WHERE " + " AND ".join(where_clauses)
    query += " ORDER BY datetime(created_at) DESC, id DESC"

    merged_rows = []
    conns = _get_user_db_connections(include_backend=True)
    try:
        for _name, conn, _path in conns:
            cur = conn.cursor()
            create_user_tables(cur)
            conn.commit()
            rows = cur.execute(query, where_args).fetchall()
            merged_rows.extend([dict(row) for row in rows])
    finally:
        _close_user_db_connections(conns)

    merged_rows = _dedupe_activity_rows(merged_rows)
    merged_rows.sort(key=lambda row: str(row.get('created_at') or ''), reverse=True)
    return merged_rows[:limit]





def authenticate_owner_login(pin):
    pin = str(pin or '').strip()
    if len(pin) != 4 or not pin.isdigit():
        return False, 'PIN must be exactly 4 digits', None

    conns = _get_user_db_connections(include_backend=True)
    matches = []
    try:
        for _name, conn, _path in conns:
            cursor = conn.cursor()
            create_user_tables(cursor)
            seed_users_if_needed(cursor)
            conn.commit()
            row = cursor.execute(
                """
                SELECT
                    id,
                    name,
                    role,
                    pin,
                    COALESCE(is_active, 1) AS is_active,
                    COALESCE(has_full_access, 0) AS has_full_access,
                    last_login_at
                FROM users
                WHERE pin = ?
                LIMIT 1
                """,
                (pin,),
            ).fetchone()
            if row:
                matches.append((conn, cursor, dict(row)))

        if not matches:
            admin_conn = get_db()
            try:
                admin_cursor = admin_conn.cursor()
                create_user_tables(admin_cursor)
                insert_user_log(
                    admin_cursor,
                    actor_user_id=None,
                    actor_name='Unknown',
                    action_type='login_failed',
                    target_user_id=None,
                    target_user_name=None,
                    description='Admin app login failed',
                )
                admin_conn.commit()
            finally:
                admin_conn.close()
            return False, 'Invalid PIN', None

        primary = matches[0][2]
        is_active = parse_int(primary.get('is_active'), 1) == 1
        role = _normalize_user_role(primary.get('role'))
        has_full_access = parse_int(primary.get('has_full_access'), 0) == 1
        name = str(primary.get('name') or 'User').strip() or 'User'

        if not is_active:
            return False, 'This user is inactive', None

        if role != 'manager' and not has_full_access:
            return False, 'Only managers or full-access users can access Admin App', None

        now = datetime.now().astimezone().isoformat()
        for conn, cursor, row in matches:
            cursor.execute(
                """
                UPDATE users
                SET last_login_at = ?,
                    updated_at = ?
                WHERE id = ?
                """,
                (now, now, row['id']),
            )
            insert_user_log(
                cursor,
                actor_user_id=row['id'],
                actor_name=row['name'],
                action_type='login_success',
                target_user_id=row['id'],
                target_user_name=row['name'],
                description=f"{row['name']} logged in from Admin Mobile",
                created_at=now,
            )
            conn.commit()

        return True, 'success', {
            'id': parse_int(primary.get('id'), 0),
            'name': name,
            'role': role,
            'is_active': True,
            'has_full_access': has_full_access,
            'last_login_at': now,
        }
    finally:
        _close_user_db_connections(conns)


def record_owner_logout(user_id=None, user_name='Owner'):
    safe_name = str(user_name or 'Owner').strip() or 'Owner'
    now = datetime.now().astimezone().isoformat()
    conns = _get_user_db_connections(include_backend=True)
    try:
        for _name, conn, _path in conns:
            cursor = conn.cursor()
            create_user_tables(cursor)
            insert_user_log(
                cursor,
                actor_user_id=parse_int(user_id, 0) or None,
                actor_name=safe_name,
                action_type='logout',
                target_user_id=parse_int(user_id, 0) or None,
                target_user_name=safe_name,
                description=f'{safe_name} logged out from Admin Mobile',
                created_at=now,
            )
            conn.commit()
    finally:
        _close_user_db_connections(conns)


def build_data_backup(cursor):
    create_business_info_table(cursor)
    seed_business_info_if_needed(cursor)
    create_user_tables(cursor)
    create_customer_product_prices_table(cursor)
    create_sale_items_table(cursor)

    def query_rows(sql, args=()):
        return [dict(row) for row in cursor.execute(sql, args).fetchall()]

    backup = {
        'status': 'success',
        'generated_at': datetime.now().astimezone().isoformat(),
        'source': 'Food City Admin App',
        'meta': {
            'backend_db_path': os.path.abspath(DB_PATH),
            'pos_db_path': os.path.abspath(POS_DB_PATH),
            'pos_db_present': os.path.exists(POS_DB_PATH),
        },
        'business_info': get_business_info(cursor),
        'customers': fetch_customers(cursor, {'include_inactive': ['1'], 'limit': ['500']}),
        'products': fetch_products(cursor),
        'suppliers': query_rows('SELECT * FROM suppliers ORDER BY name COLLATE NOCASE ASC'),
        'stock_receipts': query_rows('SELECT * FROM stock_receipts ORDER BY datetime(created_at) DESC, id DESC'),
        'inventory_history': query_rows('SELECT * FROM inventory_history ORDER BY datetime(created_at) DESC, id DESC'),
        'sales': query_rows('SELECT * FROM sales ORDER BY datetime(created_at) DESC, id DESC'),
        'sale_items': query_rows('SELECT * FROM sale_items ORDER BY sale_id DESC, id ASC'),
        'customer_product_prices': query_rows('SELECT * FROM customer_product_prices ORDER BY customer_id ASC, product_name_snapshot COLLATE NOCASE ASC'),
        'customer_ledger': query_rows('SELECT * FROM customer_ledger ORDER BY datetime(created_at) DESC, id DESC'),
        'customer_payments': query_rows('SELECT * FROM customer_payments ORDER BY datetime(created_at) DESC, id DESC'),
        'owner_users': get_owner_users(cursor, {'search': [''], 'role': ['all'], 'status': ['all']}),
        'owner_activity_logs': get_owner_activity_logs(cursor, {'search': [''], 'filter': ['all'], 'limit': ['500']}),
    }
    return backup

def _active_manager_count(cursor, excluding_user_id=None):
    query = """
        SELECT COUNT(*) AS count
        FROM users
        WHERE role = 'manager' AND COALESCE(is_active, 1) = 1
    """
    args = []
    if excluding_user_id is not None:
        query += ' AND id != ?'
        args.append(excluding_user_id)
    row = cursor.execute(query, args).fetchone()
    return parse_int(row['count'] if row else 0, 0)


def create_owner_user(cursor, body):
    create_user_tables(cursor)
    seed_users_if_needed(cursor)

    name = str(body.get('name', '') or '').strip()
    role = _normalize_user_role(body.get('role', 'cashier'))
    pin = str(body.get('pin', '') or '').strip()
    actor_name = str(body.get('actor_name', 'Admin Mobile') or 'Admin Mobile').strip() or 'Admin Mobile'

    if not name:
        return False, 'User name is required'
    if len(pin) != 4 or not pin.isdigit():
        return False, 'PIN must be exactly 4 digits'

    duplicate = cursor.execute(
        'SELECT id FROM users WHERE pin = ? LIMIT 1',
        (pin,),
    ).fetchone()
    if duplicate:
        return False, 'PIN is already used by another user'

    now = datetime.now().astimezone().isoformat()
    cursor.execute(
        """
        INSERT INTO users (
            name, role, pin, is_active, has_full_access,
            created_at, updated_at, last_login_at, created_by, updated_by
        )
        VALUES (?, ?, ?, 1, 0, ?, ?, NULL, NULL, NULL)
        """,
        (name, role, pin, now, now),
    )
    user_id = cursor.lastrowid
    role_label = 'Manager' if role == 'manager' else 'Cashier'
    insert_user_log(
        cursor,
        actor_user_id=None,
        actor_name=actor_name,
        action_type='user_created',
        target_user_id=user_id,
        target_user_name=name,
        description=f'Created user {name} ({role_label})',
        created_at=now,
    )
    return True, 'success'


def update_owner_user(cursor, body):
    create_user_tables(cursor)
    seed_users_if_needed(cursor)

    user_id = parse_int(body.get('user_id'), 0)
    name = str(body.get('name', '') or '').strip()
    role = _normalize_user_role(body.get('role', 'cashier'))
    actor_name = str(body.get('actor_name', 'Admin Mobile') or 'Admin Mobile').strip() or 'Admin Mobile'

    if user_id <= 0:
        return False, 'Invalid user'
    if not name:
        return False, 'User name is required'

    row = cursor.execute(
        'SELECT id, name, role, COALESCE(is_active, 1) AS is_active FROM users WHERE id = ? LIMIT 1',
        (user_id,),
    ).fetchone()
    if not row:
        return False, 'User not found'

    old_name = str(row['name'] or '').strip()
    old_role = _normalize_user_role(row['role'])
    is_active = parse_int(row['is_active'], 1) == 1

    if old_role == 'manager' and role != 'manager' and is_active:
        if _active_manager_count(cursor) <= 1:
            return False, 'You cannot change the last active manager to cashier'

    now = datetime.now().astimezone().isoformat()
    updates_has_full = 0 if role == 'manager' else None
    if updates_has_full is None:
        cursor.execute(
            'UPDATE users SET name = ?, role = ?, updated_at = ?, updated_by = NULL WHERE id = ?',
            (name, role, now, user_id),
        )
    else:
        cursor.execute(
            'UPDATE users SET name = ?, role = ?, has_full_access = 0, updated_at = ?, updated_by = NULL WHERE id = ?',
            (name, role, now, user_id),
        )

    if old_role != role:
        description = f'Changed role for {name} from {"Manager" if old_role == "manager" else "Cashier"} to {"Manager" if role == "manager" else "Cashier"}'
        action_type = 'role_changed'
    elif old_name != name:
        description = f'Renamed user {old_name} to {name}'
        action_type = 'user_updated'
    else:
        description = f'Updated user {name} ({"Manager" if role == "manager" else "Cashier"}) details'
        action_type = 'user_updated'

    insert_user_log(
        cursor,
        actor_user_id=None,
        actor_name=actor_name,
        action_type=action_type,
        target_user_id=user_id,
        target_user_name=name,
        description=description,
        created_at=now,
    )
    return True, 'success'


def reset_owner_user_pin(cursor, body):
    create_user_tables(cursor)
    seed_users_if_needed(cursor)

    user_id = parse_int(body.get('user_id'), 0)
    new_pin = str(body.get('new_pin', '') or '').strip()
    actor_name = str(body.get('actor_name', 'Admin Mobile') or 'Admin Mobile').strip() or 'Admin Mobile'

    if user_id <= 0:
        return False, 'Invalid user'
    if len(new_pin) != 4 or not new_pin.isdigit():
        return False, 'PIN must be exactly 4 digits'

    row = cursor.execute('SELECT id, name FROM users WHERE id = ? LIMIT 1', (user_id,)).fetchone()
    if not row:
        return False, 'User not found'

    duplicate = cursor.execute(
        'SELECT id FROM users WHERE pin = ? AND id != ? LIMIT 1',
        (new_pin, user_id),
    ).fetchone()
    if duplicate:
        return False, 'PIN is already used by another user'

    now = datetime.now().astimezone().isoformat()
    cursor.execute(
        'UPDATE users SET pin = ?, updated_at = ?, updated_by = NULL WHERE id = ?',
        (new_pin, now, user_id),
    )
    target_name = str(row['name'] or 'User')
    insert_user_log(
        cursor,
        actor_user_id=None,
        actor_name=actor_name,
        action_type='pin_reset',
        target_user_id=user_id,
        target_user_name=target_name,
        description=f'Reset PIN for {target_name}',
        created_at=now,
    )
    return True, 'success'


def set_owner_user_active_status(cursor, body):
    create_user_tables(cursor)
    seed_users_if_needed(cursor)

    user_id = parse_int(body.get('user_id'), 0)
    is_active = normalize_bool(body.get('is_active'), True)
    actor_name = str(body.get('actor_name', 'Admin Mobile') or 'Admin Mobile').strip() or 'Admin Mobile'

    if user_id <= 0:
        return False, 'Invalid user'

    row = cursor.execute(
        'SELECT id, name, role, COALESCE(is_active, 1) AS is_active FROM users WHERE id = ? LIMIT 1',
        (user_id,),
    ).fetchone()
    if not row:
        return False, 'User not found'

    current_active = parse_int(row['is_active'], 1) == 1
    current_role = _normalize_user_role(row['role'])
    target_name = str(row['name'] or 'User').strip() or 'User'

    if current_active == is_active:
        return True, 'success'

    if not is_active and current_role == 'manager' and _active_manager_count(cursor) <= 1:
        return False, 'You cannot deactivate the last active manager'

    now = datetime.now().astimezone().isoformat()
    cursor.execute(
        'UPDATE users SET is_active = ?, updated_at = ?, updated_by = NULL WHERE id = ?',
        (1 if is_active else 0, now, user_id),
    )
    action_type = 'user_reactivated' if is_active else 'user_deactivated'
    description = ('Reactivated user ' if is_active else 'Deactivated user ') + target_name
    insert_user_log(
        cursor,
        actor_user_id=None,
        actor_name=actor_name,
        action_type=action_type,
        target_user_id=user_id,
        target_user_name=target_name,
        description=description,
        created_at=now,
    )
    return True, 'success'


def set_owner_user_full_access(cursor, body):
    create_user_tables(cursor)
    seed_users_if_needed(cursor)

    user_id = parse_int(body.get('user_id'), 0)
    has_full_access = normalize_bool(body.get('has_full_access'), False)
    actor_name = str(body.get('actor_name', 'Admin Mobile') or 'Admin Mobile').strip() or 'Admin Mobile'

    if user_id <= 0:
        return False, 'Invalid user'

    row = cursor.execute(
        'SELECT id, name, role, COALESCE(has_full_access, 0) AS has_full_access FROM users WHERE id = ? LIMIT 1',
        (user_id,),
    ).fetchone()
    if not row:
        return False, 'User not found'

    role = _normalize_user_role(row['role'])
    if role == 'manager':
        return False, 'Managers already have full access by role'

    current_full = parse_int(row['has_full_access'], 0) == 1
    if current_full == has_full_access:
        return True, 'success'

    target_name = str(row['name'] or 'User').strip() or 'User'
    now = datetime.now().astimezone().isoformat()
    cursor.execute(
        'UPDATE users SET has_full_access = ?, updated_at = ?, updated_by = NULL WHERE id = ?',
        (1 if has_full_access else 0, now, user_id),
    )
    action_type = 'full_access_granted' if has_full_access else 'full_access_revoked'
    description = ('Granted full access to ' if has_full_access else 'Removed full access from ') + target_name
    insert_user_log(
        cursor,
        actor_user_id=None,
        actor_name=actor_name,
        action_type=action_type,
        target_user_id=user_id,
        target_user_name=target_name,
        description=description,
        created_at=now,
    )
    return True, 'success'
def init_db():
    conn = get_db()
    c = conn.cursor()

    c.execute(
        """
        CREATE TABLE IF NOT EXISTS products (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            barcode TEXT UNIQUE,
            name TEXT,
            price REAL,
            stock INTEGER,
            updated_at TEXT DEFAULT (datetime('now'))
        )
        """
    )

    ensure_column(c, "products", "category", "category TEXT DEFAULT 'General'")
    ensure_column(c, "products", "quantity_type", "quantity_type TEXT DEFAULT 'unit'")
    ensure_column(c, "products", "unit_label", "unit_label TEXT DEFAULT 'pcs'")
    ensure_column(c, "products", "cost_price", "cost_price REAL DEFAULT 0")
    ensure_column(c, "products", "selling_price", "selling_price REAL DEFAULT 0")
    ensure_column(c, "products", "wholesale_price", "wholesale_price REAL DEFAULT 0")
    ensure_column(c, "products", "sale_price", "sale_price REAL")
    ensure_column(c, "products", "sale_enabled", "sale_enabled INTEGER DEFAULT 0")
    ensure_column(c, "products", "min_stock_level", "min_stock_level INTEGER DEFAULT 0")
    ensure_column(c, "products", "is_active", "is_active INTEGER DEFAULT 1")
    ensure_column(c, "products", "last_price_updated_at", "last_price_updated_at TEXT")

    c.execute(
        f"""
        UPDATE products
        SET category = COALESCE(NULLIF(category, ''), 'General'),
            quantity_type = CASE
                WHEN LOWER(COALESCE(quantity_type, '')) = 'weight' THEN 'weight'
                ELSE 'unit'
            END,
            unit_label = CASE
                WHEN TRIM(COALESCE(unit_label, '')) != '' THEN TRIM(unit_label)
                WHEN LOWER(COALESCE(quantity_type, 'unit')) = 'weight' THEN 'kg'
                ELSE 'pcs'
            END,
            selling_price = COALESCE(NULLIF(selling_price, 0), price, 0),
            price = COALESCE(NULLIF(price, 0), selling_price, 0),
            wholesale_price = CASE
                WHEN COALESCE(wholesale_price, 0) <= 0 THEN COALESCE(NULLIF(selling_price, 0), price, 0)
                ELSE wholesale_price
            END,
            sale_enabled = COALESCE(sale_enabled, 0),
            min_stock_level = COALESCE(min_stock_level, 0),
            is_active = COALESCE(is_active, 1),
            updated_at = COALESCE(updated_at, {now_sql()}),
            last_price_updated_at = COALESCE(last_price_updated_at, updated_at)
        """
    )

    c.execute(
        """
        CREATE TABLE IF NOT EXISTS sales (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            total_amount REAL,
            cashier_name TEXT,
            branch TEXT,
            vendor TEXT,
            items TEXT,
            created_at TEXT DEFAULT (datetime('now'))
        )
        """
    )

    ensure_column(c, "sales", "subtotal_amount", "subtotal_amount REAL DEFAULT 0")
    ensure_column(c, "sales", "discount_amount", "discount_amount REAL DEFAULT 0")
    ensure_column(c, "sales", "discount_type", "discount_type TEXT")
    ensure_column(c, "sales", "payment_method", "payment_method TEXT")
    ensure_column(c, "sales", "transaction_type", "transaction_type TEXT DEFAULT 'sale'")
    ensure_column(c, "sales", "items_count", "items_count INTEGER DEFAULT 0")
    ensure_column(c, "sales", "gross_profit", "gross_profit REAL DEFAULT 0")
    ensure_customer_sales_columns(c)
    create_customer_credit_tables(c)
    create_customer_product_prices_table(c)
    create_sale_items_table(c)

    c.execute(
        """
        CREATE TABLE IF NOT EXISTS suppliers (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT,
            phone TEXT
        )
        """
    )

    c.execute(
        """
        CREATE TABLE IF NOT EXISTS stock_receipts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            barcode TEXT,
            quantity INTEGER,
            supplier_id INTEGER,
            cost REAL,
            created_at TEXT DEFAULT (datetime('now'))
        )
        """
    )

    c.execute(
        """
        CREATE TABLE IF NOT EXISTS supplier_product_mappings (
            barcode TEXT PRIMARY KEY,
            supplier_id INTEGER NOT NULL,
            updated_at TEXT DEFAULT (datetime('now'))
        )
        """
    )

    c.execute(
        """
        CREATE TABLE IF NOT EXISTS inventory_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            barcode TEXT NOT NULL,
            movement_type TEXT NOT NULL,
            quantity INTEGER NOT NULL,
            reason TEXT,
            reference_type TEXT,
            reference_id INTEGER,
            created_at TEXT DEFAULT (datetime('now'))
        )
        """
    )

    latest_supplier_rows = c.execute(
        """
        SELECT sr.barcode, sr.supplier_id
        FROM stock_receipts sr
        JOIN (
            SELECT barcode, MAX(id) AS latest_id
            FROM stock_receipts
            WHERE supplier_id IS NOT NULL AND supplier_id > 0
            GROUP BY barcode
        ) latest ON latest.latest_id = sr.id
        WHERE sr.barcode IS NOT NULL
          AND sr.barcode != ''
          AND sr.supplier_id IS NOT NULL
          AND sr.supplier_id > 0
        """
    ).fetchall()

    for row in latest_supplier_rows:
        c.execute(
            f"""
            INSERT INTO supplier_product_mappings (
                barcode,
                supplier_id,
                updated_at
            )
            VALUES (?, ?, {now_sql()})
            ON CONFLICT(barcode) DO UPDATE SET
                supplier_id = excluded.supplier_id,
                updated_at = excluded.updated_at
            """,
            (str(row["barcode"]), parse_int(row["supplier_id"], 0)),
        )

    if c.execute("SELECT COUNT(*) FROM products").fetchone()[0] == 0:
        products = [
            {
                "barcode": "4791044000123",
                "name": "Munchee Super Cream Cracker 500g",
                "selling_price": 550.00,
                "wholesale_price": 500.00,
                "sale_price": None,
                "sale_enabled": 0,
                "cost_price": 420.00,
                "stock": 100,
                "min_stock_level": 10,
            },
            {
                "barcode": "4792011001234",
                "name": "Anchor Milk Powder 400g",
                "selling_price": 1100.00,
                "wholesale_price": 1050.00,
                "sale_price": None,
                "sale_enabled": 0,
                "cost_price": 920.00,
                "stock": 50,
                "min_stock_level": 8,
            },
            {
                "barcode": "4792022005678",
                "name": "Saman Halmassa 425g",
                "selling_price": 650.00,
                "wholesale_price": 620.00,
                "sale_price": None,
                "sale_enabled": 0,
                "cost_price": 540.00,
                "stock": 30,
                "min_stock_level": 6,
            },
            {
                "barcode": "4793033009999",
                "name": "Kist Strawberry Jam 500g",
                "selling_price": 580.00,
                "wholesale_price": 555.00,
                "sale_price": None,
                "sale_enabled": 0,
                "cost_price": 470.00,
                "stock": 40,
                "min_stock_level": 8,
            },
        ]
        for item in products:
            c.execute(
                f"""
                INSERT INTO products (
                    barcode,
                    name,
                    category,
                    price,
                    cost_price,
                    selling_price,
                    wholesale_price,
                    sale_price,
                    sale_enabled,
                    stock,
                    min_stock_level,
                    is_active,
                    updated_at,
                    last_price_updated_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, {now_sql()}, {now_sql()})
                """,
                (
                    item["barcode"],
                    item["name"],
                    "General",
                    item["selling_price"],
                    item["cost_price"],
                    item["selling_price"],
                    item["wholesale_price"],
                    item["sale_price"],
                    item["sale_enabled"],
                    item["stock"],
                    item["min_stock_level"],
                ),
            )
        print("✅ Seeded 4 mock products")

    if c.execute("SELECT COUNT(*) FROM suppliers").fetchone()[0] == 0:
        suppliers = [
            ("Maliban Distributor", "077-1234567"),
            ("Fonterra Lanka", "077-9876543"),
        ]
        for name, phone in suppliers:
            c.execute(
                "INSERT INTO suppliers (name, phone) VALUES (?, ?)",
                (name, phone),
            )
        print("✅ Seeded 2 mock suppliers")


    create_business_info_table(c)
    seed_business_info_if_needed(c)

    create_user_tables(c)
    seed_users_if_needed(c)

    conn.commit()
    conn.close()


class APIHandler(BaseHTTPRequestHandler):
    def _set_headers(self, status=200):
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.end_headers()

    def do_OPTIONS(self):
        self._set_headers()

    def do_GET(self):
        parsed = urlparse(self.path)
        params = parse_qs(parsed.query)
        action = params.get("action", [None])[0]

        conn = get_db()
        c = conn.cursor()

        if action == "get_products":
            result = fetch_products(c)
            self._set_headers()
            self.wfile.write(json.dumps(result).encode())

        elif action == "get_sales":
            rows = c.execute(
                """
                SELECT cashier_name,
                       SUM(CASE WHEN COALESCE(transaction_type, 'sale') = 'refund' THEN -COALESCE(total_amount, 0) ELSE COALESCE(total_amount, 0) END) AS total_sales,
                       SUM(CASE WHEN COALESCE(transaction_type, 'sale') = 'sale' THEN 1 ELSE 0 END) AS transaction_count
                FROM sales
                WHERE DATE(created_at) = DATE('now','localtime')
                GROUP BY cashier_name
                """
            ).fetchall()

            cashier_sales = [dict(r) for r in rows]
            grand_total = sum(float(r["total_sales"] or 0) for r in rows) if rows else 0

            self._set_headers()
            self.wfile.write(
                json.dumps(
                    {
                        "status": "success",
                        "grand_total": grand_total,
                        "cashier_sales": cashier_sales,
                    }
                ).encode()
            )


        elif action == "get_business_info":
            info = get_business_info(c)
            self._set_headers()
            self.wfile.write(
                json.dumps({
                    "status": "success",
                    "business_info": info,
                }).encode()
            )

        elif action == "get_owner_user_summary":
            owner_conn = get_owner_users_db()
            owner_cursor = owner_conn.cursor()
            try:
                summary = get_owner_user_summary(owner_cursor)
                self._set_headers()
                self.wfile.write(
                    json.dumps({
                        "status": "success",
                        "summary": summary,
                    }).encode()
                )
            finally:
                owner_conn.close()

        elif action == "get_owner_users":
            owner_conn = get_owner_users_db()
            owner_cursor = owner_conn.cursor()
            try:
                users = get_owner_users(owner_cursor, params)
                self._set_headers()
                self.wfile.write(
                    json.dumps({
                        "status": "success",
                        "users": users,
                    }).encode()
                )
            finally:
                owner_conn.close()

        elif action == "get_owner_activity_logs":
            owner_conn = get_owner_users_db()
            owner_cursor = owner_conn.cursor()
            try:
                logs = get_owner_activity_logs(owner_cursor, params)
                self._set_headers()
                self.wfile.write(
                    json.dumps({
                        "status": "success",
                        "logs": logs,
                    }).encode()
                )
            finally:
                owner_conn.close()

        elif action == "export_data_backup":
            backup = build_data_backup(c)
            self._set_headers()
            self.wfile.write(json.dumps(backup).encode())

        elif action == "get_owner_dashboard":
            today_rows = _sales_rows_between(
                c,
                "datetime('now','localtime','start of day')",
                "datetime('now','localtime','+1 day','start of day')",
            )
            summary_data = _build_owner_summary_from_rows(today_rows)
            trend = _owner_trend(c, days=7)

            self._set_headers()
            self.wfile.write(
                json.dumps(
                    {
                        "status": "success",
                        "summary": summary_data["summary"],
                        "trend": trend,
                        "top_products": summary_data["top_products"],
                    }
                ).encode()
            )

        elif action == "get_owner_alerts":
            alerts = _build_owner_alerts(c)
            self._set_headers()
            self.wfile.write(
                json.dumps(
                    {
                        "status": "success",
                        "alerts": alerts,
                    }
                ).encode()
            )

        elif action == "get_owner_sales_report":
            report = _build_owner_sales_report(c, params)
            self._set_headers()
            self.wfile.write(
                json.dumps(
                    {
                        "status": "success",
                        **report,
                    }
                ).encode()
            )

        elif action == "get_suppliers":
            rows = c.execute("SELECT * FROM suppliers").fetchall()
            result = [dict(r) for r in rows]
            self._set_headers()
            self.wfile.write(json.dumps(result).encode())

        elif action == "get_customers":
            result = fetch_customers(c, params)
            self._set_headers()
            self.wfile.write(
                json.dumps({"status": "success", "customers": result}).encode()
            )

        elif action == "get_customer_product_prices":
            create_customer_product_prices_table(c)
            customer_id = parse_int(params.get("customer_id", params.get("id", ["0"]))[0], 0)
            active_only = normalize_bool(params.get("active_only", ["0"])[0], False)
            query = "SELECT * FROM customer_product_prices WHERE customer_id = ?"
            args = [customer_id]
            if active_only:
                query += " AND COALESCE(is_active, 1) = 1"
            query += " ORDER BY COALESCE(is_active, 1) DESC, product_name_snapshot COLLATE NOCASE ASC"
            result = [dict(row) for row in c.execute(query, args).fetchall()]
            self._set_headers()
            self.wfile.write(
                json.dumps({"status": "success", "product_prices": result}).encode()
            )

        elif action == "get_customer_summary":
            customer_id = params.get("customer_id", params.get("id", ["0"]))[0]
            summary = get_customer_summary(c, customer_id)
            self._set_headers()
            self.wfile.write(
                json.dumps({"status": "success", "summary": summary}).encode()
            )

        elif action == "get_customer_purchase_history":
            customer_id = params.get("customer_id", params.get("id", ["0"]))[0]
            limit = params.get("limit", ["100"])[0]
            history = get_customer_purchase_history(c, customer_id, limit=limit)
            self._set_headers()
            self.wfile.write(
                json.dumps({"status": "success", "history": history}).encode()
            )


        elif action == "get_customer_ledger":
            customer_id = params.get("customer_id", params.get("id", ["0"]))[0]
            limit = params.get("limit", ["300"])[0]
            ledger = get_customer_ledger_rows(c, customer_id, limit=limit)
            self._set_headers()
            self.wfile.write(
                json.dumps({"status": "success", "ledger": ledger}).encode()
            )

        elif action == "get_customer_credit_summary":
            customer_id = parse_int(params.get("customer_id", params.get("id", ["0"]))[0], 0)
            balance = update_customer_cached_credit_balance(c, customer_id)
            row = c.execute(
                """
                SELECT id AS customer_id,
                       COALESCE(credit_enabled, 0) AS credit_enabled,
                       COALESCE(credit_limit, 0) AS credit_limit,
                       COALESCE(current_credit_balance, 0) AS current_credit_balance,
                       COALESCE(credit_status, 'normal') AS credit_status,
                       credit_note
                FROM customers
                WHERE id = ?
                LIMIT 1
                """,
                (customer_id,),
            ).fetchone()
            result = dict(row) if row else {"customer_id": customer_id, "current_credit_balance": balance}
            self._set_headers()
            self.wfile.write(
                json.dumps({"status": "success", "summary": result}).encode()
            )

        elif action == "get_credit_customers_report":
            include_zero = normalize_bool(params.get("include_zero", ["0"])[0], False)
            limit = params.get("limit", ["300"])[0]
            rows = get_credit_customers_report_rows(c, include_zero=include_zero, limit=limit)
            self._set_headers()
            self.wfile.write(
                json.dumps({"status": "success", "customers": rows}).encode()
            )

        elif action == "get_inventory_history":
            barcode = params.get("barcode", [""])[0].strip()

            if not barcode:
                self._set_headers(400)
                self.wfile.write(
                    json.dumps(
                        {"status": "error", "message": "barcode is required"}
                    ).encode()
                )
            else:
                rows = c.execute(
                    """
                    SELECT *
                    FROM inventory_history
                    WHERE barcode = ?
                    ORDER BY datetime(created_at) DESC, id DESC
                    """,
                    (barcode,),
                ).fetchall()

                result = [dict(r) for r in rows]
                self._set_headers()
                self.wfile.write(
                    json.dumps({"status": "success", "history": result}).encode()
                )

        elif action == "get_product_supplier_contact":
            barcode = params.get("barcode", [""])[0].strip()

            if not barcode:
                self._set_headers(400)
                self.wfile.write(
                    json.dumps(
                        {"status": "error", "message": "barcode is required"}
                    ).encode()
                )
            else:
                contact = _latest_supplier_contact_for_barcode(c, barcode)
                self._set_headers()
                self.wfile.write(
                    json.dumps({"status": "success", "contact": contact}).encode()
                )

        else:
            self._set_headers(404)
            self.wfile.write(
                json.dumps({"status": "error", "message": "Unknown action"}).encode()
            )

        conn.close()

    def do_POST(self):
        parsed = urlparse(self.path)
        params = parse_qs(parsed.query)
        action = params.get("action", [None])[0]

        content_length = int(self.headers.get("Content-Length", 0))
        body = (
            json.loads(self.rfile.read(content_length)) if content_length > 0 else {}
        )

        conn = get_db()
        c = conn.cursor()

        if action == "owner_login":
            ok, message, user = authenticate_owner_login(body.get('pin', ''))
            if not ok:
                self._set_headers(400)
                self.wfile.write(json.dumps({"status": "error", "message": message}).encode())
            else:
                self._set_headers()
                self.wfile.write(json.dumps({"status": "success", "user": user}).encode())

        elif action == "owner_logout":
            record_owner_logout(
                user_id=body.get('user_id'),
                user_name=body.get('user_name', 'Owner'),
            )
            self._set_headers()
            self.wfile.write(json.dumps({"status": "success"}).encode())

        elif action == "pos_sync":
            sync_type = str(body.get("type", "")).strip().upper()
            data = body.get("data", {})

            if isinstance(data, str):
                data = json.loads(data)

            if sync_type == "SALE":
                transaction_type = str(data.get("transaction_type", "sale")).lower()
                items = data.get("items", [])

                for item in items:
                    product = item.get("product", {})
                    barcode = str(product.get("barcode", "")).strip()
                    qty = _extract_item_quantity(item)

                    if not barcode:
                        self._set_headers(400)
                        self.wfile.write(
                            json.dumps(
                                {"status": "error", "message": "Missing product barcode"}
                            ).encode()
                        )
                        conn.close()
                        return

                    if qty <= 0:
                        self._set_headers(400)
                        self.wfile.write(
                            json.dumps(
                                {"status": "error", "message": f"Invalid quantity for {barcode}"}
                            ).encode()
                        )
                        conn.close()
                        return

                    row = c.execute(
                        "SELECT stock FROM products WHERE barcode = ?",
                        (barcode,),
                    ).fetchone()

                    if not row:
                        self._set_headers(404)
                        self.wfile.write(
                            json.dumps(
                                {"status": "error", "message": f"Product not found: {barcode}"}
                            ).encode()
                        )
                        conn.close()
                        return

                    current_stock = round_quantity(row["stock"])
                    if transaction_type == "sale" and current_stock + 0.000001 < qty:
                        self._set_headers(400)
                        self.wfile.write(
                            json.dumps(
                                {
                                    "status": "error",
                                    "message": f"Insufficient backend stock for {barcode}. Available: {format_quantity(current_stock)}, requested: {format_quantity(qty)}",
                                }
                            ).encode()
                        )
                        conn.close()
                        return

                subtotal_amount = parse_float(data.get("subtotal_amount", 0), 0.0)
                total_amount = parse_float(data.get("total_amount", 0), 0.0)
                discount_amount = parse_float(data.get("discount_amount", 0), 0.0)
                payment_method = str(data.get("payment_method", "") or "").strip().lower()
                if subtotal_amount <= 0:
                    subtotal_amount = total_amount + max(discount_amount, 0.0)
                if discount_amount <= 0 and subtotal_amount > total_amount:
                    discount_amount = subtotal_amount - total_amount
                items_count = round_quantity(
                    sum(max(_extract_item_quantity(item), 0) for item in items)
                )
                gross_profit = 0.0
                for item in items:
                    quantity = max(_extract_item_quantity(item), 0)
                    barcode = _extract_item_barcode(item)
                    unit_price = max(_extract_item_price(item), 0.0)
                    product_row = get_product_row(c, barcode) if barcode else None
                    unit_cost = parse_float(product_row["cost_price"], 0.0) if product_row else 0.0
                    gross_profit += (unit_price - unit_cost) * quantity

                created_at = str(data.get("created_at", "") or "").strip() or datetime.now().astimezone().isoformat()
                pos_sale_id = parse_int(data.get("id", data.get("sale_id", 0)), 0) or None
                ensure_customer_sales_columns(c)
                customer_id = parse_int(data.get("customer_id"), 0) or None
                customer_name_snapshot = clean_optional_text(
                    data.get("customer_name_snapshot")
                    or data.get("customer_name")
                    or data.get("selected_customer_name")
                )
                customer_phone_snapshot = clean_optional_text(
                    data.get("customer_phone_snapshot")
                    or data.get("customer_phone")
                    or data.get("selected_customer_phone")
                )
                customer_code_snapshot = clean_optional_text(
                    data.get("customer_code_snapshot")
                    or data.get("customer_code")
                    or data.get("selected_customer_code")
                )

                c.execute(
                    """
                    INSERT INTO sales (
                        total_amount,
                        subtotal_amount,
                        discount_amount,
                        discount_type,
                        payment_method,
                        transaction_type,
                        items_count,
                        gross_profit,
                        cashier_name,
                        branch,
                        vendor,
                        items,
                        created_at,
                        pos_sale_id,
                        customer_id,
                        customer_name_snapshot,
                        customer_phone_snapshot,
                        customer_code_snapshot
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        total_amount,
                        subtotal_amount,
                        discount_amount,
                        str(data.get("discount_type", "") or ""),
                        payment_method,
                        transaction_type,
                        items_count,
                        gross_profit,
                        data.get("cashier", "Unknown"),
                        data.get("branch", ""),
                        data.get("vendor", ""),
                        json.dumps(items),
                        created_at,
                        pos_sale_id,
                        customer_id,
                        customer_name_snapshot,
                        customer_phone_snapshot,
                        customer_code_snapshot,
                    ),
                )
                sale_id = c.lastrowid
                insert_sale_item_snapshots(c, sale_id, items, created_at)

                for item in items:
                    product = item.get("product", {})
                    barcode = str(product.get("barcode", "")).strip()
                    qty = _extract_item_quantity(item)

                    stock_delta = qty if transaction_type == "refund" else -qty

                    c.execute(
                        f"""
                        UPDATE products
                        SET stock = stock + ?, updated_at = {now_sql()}
                        WHERE barcode = ?
                        """,
                        (stock_delta, barcode),
                    )

                    movement_type = "refund" if transaction_type == "refund" else "sale"
                    reason = (
                        f"Refund processed by {data.get('cashier', 'Unknown')}"
                        if transaction_type == "refund"
                        else f"Sold through POS by {data.get('cashier', 'Unknown')}"
                    )

                    log_inventory_history(
                        c,
                        barcode=barcode,
                        movement_type=movement_type,
                        quantity=stock_delta,
                        reason=reason,
                        reference_type="sale",
                        reference_id=sale_id,
                    )

                conn.commit()
                print(
                    f"  ✅ {transaction_type.upper()} synced: Rs.{data.get('total_amount', 0)} by {data.get('cashier', 'Unknown')}"
                )
                self._set_headers()
                self.wfile.write(json.dumps({"status": "success"}).encode())


            elif sync_type == "CUSTOMER_CREDIT_SETTINGS":
                customer_id = handle_credit_settings_sync(c, data)
                conn.commit()
                print(f"  ✅ CUSTOMER_CREDIT_SETTINGS synced: customer #{customer_id}")
                self._set_headers()
                self.wfile.write(json.dumps({"status": "success"}).encode())

            elif sync_type == "CUSTOMER_PRICING_SETTINGS":
                customer_id = handle_customer_pricing_settings_sync(c, data)
                conn.commit()
                print(f"  CUSTOMER_PRICING_SETTINGS synced: customer #{customer_id}")
                self._set_headers()
                self.wfile.write(json.dumps({"status": "success"}).encode())

            elif sync_type in {"CUSTOMER_PRODUCT_PRICE_UPSERT", "CUSTOMER_PRODUCT_PRICE"}:
                price_id = handle_customer_product_price_sync(c, data)
                conn.commit()
                print(f"  CUSTOMER_PRODUCT_PRICE synced: rule #{price_id}")
                self._set_headers()
                self.wfile.write(json.dumps({"status": "success"}).encode())

            elif sync_type == "CREDIT_SALE_UPDATE":
                ledger_id = handle_credit_sale_update_sync(c, data)
                conn.commit()
                print(f"  ✅ CREDIT_SALE_UPDATE synced: ledger #{ledger_id}")
                self._set_headers()
                self.wfile.write(json.dumps({"status": "success"}).encode())

            elif sync_type == "CREDIT_REFUND_UPDATE":
                ledger_id = handle_credit_refund_update_sync(c, data)
                conn.commit()
                print(f"  ✅ CREDIT_REFUND_UPDATE synced: ledger #{ledger_id}")
                self._set_headers()
                self.wfile.write(json.dumps({"status": "success"}).encode())

            elif sync_type == "CUSTOMER_PAYMENT":
                payment_id = handle_customer_payment_sync(c, data)
                conn.commit()
                print(f"  ✅ CUSTOMER_PAYMENT synced: payment #{payment_id}")
                self._set_headers()
                self.wfile.write(json.dumps({"status": "success"}).encode())

            elif sync_type == "CUSTOMER_LEDGER_ADJUSTMENT":
                customer_id = upsert_customer_from_sync(c, data)
                ledger_id = insert_credit_ledger_entry(c, data, customer_id=customer_id)
                conn.commit()
                print(f"  ✅ CUSTOMER_LEDGER_ADJUSTMENT synced: ledger #{ledger_id}")
                self._set_headers()
                self.wfile.write(json.dumps({"status": "success"}).encode())

            elif sync_type == "CUSTOMER_PAYMENT_VOID":
                ledger_id = handle_customer_payment_void_sync(c, data)
                conn.commit()
                print(f"  ✅ CUSTOMER_PAYMENT_VOID synced: ledger #{ledger_id}")
                self._set_headers()
                self.wfile.write(json.dumps({"status": "success"}).encode())

            elif sync_type == "PRODUCT_CREATE":
                barcode = str(data.get("barcode", "")).strip()
                name = str(data.get("name", "")).strip()
                ok, message = create_or_update_product(
                    c,
                    barcode=barcode,
                    name=name,
                    category=data.get("category", "General"),
                    cost_price=data.get("cost_price", 0),
                    selling_price=data.get("selling_price", data.get("price", 0)),
                    wholesale_price=data.get("wholesale_price"),
                    sale_price=data.get("sale_price"),
                    sale_enabled=data.get("sale_enabled"),
                    quantity_type=data.get("quantity_type", "unit"),
                    unit_label=data.get("unit_label"),
                    opening_stock=data.get("opening_stock", data.get("stock", 0)),
                    min_stock_level=data.get("min_stock_level", 0),
                    reason=str(data.get("reason", "")).strip(),
                )
                if not ok:
                    self._set_headers(400)
                    self.wfile.write(json.dumps({"status": "error", "message": message}).encode())
                else:
                    conn.commit()
                    print(f"  ✅ PRODUCT_CREATE: {barcode} • {name}")
                    self._set_headers()
                    self.wfile.write(json.dumps({"status": "success"}).encode())

            elif sync_type == "BULK_PRODUCT_IMPORT":
                rows = data.get("rows", [])
                created_or_updated = 0

                for raw_row in rows:
                    row = dict(raw_row or {})
                    ok, message = create_or_update_product(
                        c,
                        barcode=row.get("barcode", ""),
                        name=row.get("name", ""),
                        category=row.get("category", "General"),
                        cost_price=row.get("cost_price", 0),
                        selling_price=row.get("selling_price", row.get("price", 0)),
                        wholesale_price=row.get("wholesale_price"),
                        sale_price=row.get("sale_price"),
                        sale_enabled=row.get("sale_enabled"),
                        quantity_type=row.get("quantity_type", "unit"),
                        unit_label=row.get("unit_label"),
                        opening_stock=row.get("opening_stock", row.get("stock", 0)),
                        min_stock_level=row.get("min_stock_level", 0),
                        reason="Bulk product import",
                        mirror_to_pos=False,
                    )
                    if not ok:
                        self._set_headers(400)
                        self.wfile.write(json.dumps({"status": "error", "message": message}).encode())
                        conn.close()
                        return
                    created_or_updated += 1

                conn.commit()
                print(f"  ✅ BULK_PRODUCT_IMPORT: {created_or_updated} rows")
                self._set_headers()
                self.wfile.write(json.dumps({"status": "success", "processed": created_or_updated}).encode())

            elif sync_type == "PRODUCT_UPDATE":
                barcode = str(data.get("barcode", "")).strip()
                name = str(data.get("name", "")).strip()
                ok, message = create_or_update_product(
                    c,
                    barcode=barcode,
                    name=name,
                    category=data.get("category", "General"),
                    cost_price=data.get("cost_price", 0),
                    selling_price=data.get("selling_price", data.get("price", 0)),
                    wholesale_price=data.get("wholesale_price"),
                    sale_price=data.get("sale_price"),
                    sale_enabled=data.get("sale_enabled"),
                    quantity_type=data.get("quantity_type", "unit"),
                    unit_label=data.get("unit_label"),
                    opening_stock=data.get("opening_stock", data.get("stock", 0)),
                    min_stock_level=data.get("min_stock_level", 0),
                    reason=str(data.get("reason", "")).strip() or "Product updated",
                    mirror_to_pos=False,
                )
                if not ok:
                    self._set_headers(400)
                    self.wfile.write(json.dumps({"status": "error", "message": message}).encode())
                else:
                    conn.commit()
                    print(f"  ✅ PRODUCT_UPDATE: {barcode} • {name}")
                    self._set_headers()
                    self.wfile.write(json.dumps({"status": "success"}).encode())

            elif sync_type == "PRODUCT_DELETE":
                barcode = str(data.get("barcode", "")).strip()
                ok, message = delete_product(
                    c,
                    barcode=barcode,
                    reason=str(data.get("reason", "")).strip() or "Product removed from inventory",
                    mirror_to_pos=False,
                )
                if not ok:
                    self._set_headers(400)
                    self.wfile.write(json.dumps({"status": "error", "message": message}).encode())
                else:
                    conn.commit()
                    print(f"  ✅ PRODUCT_DELETE: {barcode}")
                    self._set_headers()
                    self.wfile.write(json.dumps({"status": "success"}).encode())

            elif sync_type == "BULK_PRODUCT_DELETE":
                ok, deleted_count = bulk_delete_products(
                    c,
                    data.get("barcodes", []),
                    reason=str(data.get("reason", "")).strip() or "Bulk deleted from inventory",
                    mirror_to_pos=False,
                )
                conn.commit()
                print(f"  ✅ BULK_PRODUCT_DELETE: {deleted_count} products")
                self._set_headers()
                self.wfile.write(json.dumps({"status": "success", "deleted": deleted_count}).encode())

            elif sync_type == "PRICE_UPDATE":
                barcode = str(data.get("barcode", "")).strip()
                new_price = data.get("new_price", 0)
                price_type = str(data.get("price_type", "selling")).strip().lower()
                sale_enabled = data.get("sale_enabled")
                reason = str(data.get("reason", "")).strip()

                ok, message = update_product_price(
                    c,
                    barcode=barcode,
                    new_price=new_price,
                    price_type=price_type,
                    sale_enabled=sale_enabled,
                    reason=reason,
                )
                if not ok:
                    self._set_headers(400)
                    self.wfile.write(json.dumps({"status": "error", "message": message}).encode())
                else:
                    conn.commit()
                    print(f"  ✅ PRICE_UPDATE: {barcode} [{price_type}] → Rs.{parse_float(new_price):.2f}")
                    self._set_headers()
                    self.wfile.write(json.dumps({"status": "success"}).encode())

            elif sync_type in {"STOCK_RECEIVE", "INVENTORY_RECEIVE", "ADD_STOCK"}:
                barcode = str(data.get("barcode", "")).strip()
                quantity = data.get("quantity", 0)
                unit_cost = data.get("unit_cost", data.get("cost", 0))
                supplier_id = data.get("supplier_id", 0)
                supplier_name = str(data.get("supplier_name", "")).strip()
                reason = str(data.get("reason", "")).strip()

                ok, message, _ = update_stock_receive(
                    c,
                    barcode=barcode,
                    quantity=quantity,
                    cost=unit_cost,
                    supplier_id=supplier_id,
                    supplier_name=supplier_name,
                    reason=reason,
                )
                if not ok:
                    self._set_headers(400)
                    self.wfile.write(json.dumps({"status": "error", "message": message}).encode())
                else:
                    conn.commit()
                    print(f"  ✅ STOCK_RECEIVE: {barcode} +{parse_int(quantity)}")
                    self._set_headers()
                    self.wfile.write(json.dumps({"status": "success"}).encode())

            elif sync_type in {"STOCK_ADJUST", "INVENTORY_ADJUST"}:
                barcode = str(data.get("barcode", "")).strip()
                adjustment_type = str(data.get("adjustment_type", "")).strip().lower()
                quantity = data.get("quantity", 0)
                reason = str(data.get("reason", "")).strip()

                ok, message, resulting_stock, stock_delta = update_stock_adjustment(
                    c,
                    barcode=barcode,
                    adjustment_type=adjustment_type,
                    quantity=quantity,
                    reason=reason,
                )
                if not ok:
                    self._set_headers(400)
                    self.wfile.write(json.dumps({"status": "error", "message": message}).encode())
                else:
                    conn.commit()
                    stock_delta_value = stock_delta
                    stock_delta = int(stock_delta)
                    print(f"  ✅ STOCK_ADJUST: {barcode} {adjustment_type} ({stock_delta:+d})")
                    stock_delta = stock_delta_value
                    self._set_headers()
                    self.wfile.write(
                        json.dumps(
                            {
                                "status": "success",
                                "resulting_stock": resulting_stock,
                                "stock_delta": stock_delta,
                            }
                        ).encode()
                    )

            elif sync_type in {"MIN_STOCK_UPDATE", "UPDATE_MIN_STOCK"}:
                barcode = str(data.get("barcode", "")).strip()
                min_stock_level = data.get("min_stock_level", 0)
                reason = str(data.get("reason", "")).strip()

                ok, message = update_min_stock_level(
                    c,
                    barcode=barcode,
                    min_stock_level=min_stock_level,
                    reason=reason,
                )
                if not ok:
                    self._set_headers(400)
                    self.wfile.write(json.dumps({"status": "error", "message": message}).encode())
                else:
                    conn.commit()
                    print(f"  ✅ MIN_STOCK_UPDATE: {barcode} → {parse_int(min_stock_level)}")
                    self._set_headers()
                    self.wfile.write(json.dumps({"status": "success"}).encode())

            else:
                self._set_headers(400)
                self.wfile.write(
                    json.dumps(
                        {"status": "error", "message": f"Unsupported sync type: {sync_type}"}
                    ).encode()
                )

        elif action == "update_business_info":
            ok, message = update_business_info(c, body)
            if not ok:
                self._set_headers(400)
                self.wfile.write(json.dumps({"status": "error", "message": message}).encode())
            else:
                conn.commit()
                self._set_headers()
                self.wfile.write(json.dumps({"status": "success"}).encode())

        elif action == "create_owner_user":
            conns = _get_user_db_connections(include_backend=True)
            try:
                ok = True
                message = 'success'
                for _name, owner_conn, _path in conns:
                    owner_cursor = owner_conn.cursor()
                    create_user_tables(owner_cursor)
                    seed_users_if_needed(owner_cursor)
                    ok, message = create_owner_user(owner_cursor, body)
                    if not ok:
                        break
                if not ok:
                    for _name, owner_conn, _path in conns:
                        try:
                            owner_conn.rollback()
                        except Exception:
                            pass
                    self._set_headers(400)
                    self.wfile.write(json.dumps({"status": "error", "message": message}).encode())
                else:
                    for _name, owner_conn, _path in conns:
                        owner_conn.commit()
                    self._set_headers()
                    self.wfile.write(json.dumps({"status": "success"}).encode())
            finally:
                _close_user_db_connections(conns)

        elif action == "update_owner_user":
            conns = _get_user_db_connections(include_backend=True)
            try:
                ok = True
                message = 'success'
                for _name, owner_conn, _path in conns:
                    owner_cursor = owner_conn.cursor()
                    create_user_tables(owner_cursor)
                    seed_users_if_needed(owner_cursor)
                    ok, message = update_owner_user(owner_cursor, body)
                    if not ok:
                        break
                if not ok:
                    for _name, owner_conn, _path in conns:
                        try:
                            owner_conn.rollback()
                        except Exception:
                            pass
                    self._set_headers(400)
                    self.wfile.write(json.dumps({"status": "error", "message": message}).encode())
                else:
                    for _name, owner_conn, _path in conns:
                        owner_conn.commit()
                    self._set_headers()
                    self.wfile.write(json.dumps({"status": "success"}).encode())
            finally:
                _close_user_db_connections(conns)

        elif action == "reset_owner_user_pin":
            conns = _get_user_db_connections(include_backend=True)
            try:
                ok = True
                message = 'success'
                for _name, owner_conn, _path in conns:
                    owner_cursor = owner_conn.cursor()
                    create_user_tables(owner_cursor)
                    seed_users_if_needed(owner_cursor)
                    ok, message = reset_owner_user_pin(owner_cursor, body)
                    if not ok:
                        break
                if not ok:
                    for _name, owner_conn, _path in conns:
                        try:
                            owner_conn.rollback()
                        except Exception:
                            pass
                    self._set_headers(400)
                    self.wfile.write(json.dumps({"status": "error", "message": message}).encode())
                else:
                    for _name, owner_conn, _path in conns:
                        owner_conn.commit()
                    self._set_headers()
                    self.wfile.write(json.dumps({"status": "success"}).encode())
            finally:
                _close_user_db_connections(conns)

        elif action == "set_owner_user_active_status":
            conns = _get_user_db_connections(include_backend=True)
            try:
                ok = True
                message = 'success'
                for _name, owner_conn, _path in conns:
                    owner_cursor = owner_conn.cursor()
                    create_user_tables(owner_cursor)
                    seed_users_if_needed(owner_cursor)
                    ok, message = set_owner_user_active_status(owner_cursor, body)
                    if not ok:
                        break
                if not ok:
                    for _name, owner_conn, _path in conns:
                        try:
                            owner_conn.rollback()
                        except Exception:
                            pass
                    self._set_headers(400)
                    self.wfile.write(json.dumps({"status": "error", "message": message}).encode())
                else:
                    for _name, owner_conn, _path in conns:
                        owner_conn.commit()
                    self._set_headers()
                    self.wfile.write(json.dumps({"status": "success"}).encode())
            finally:
                _close_user_db_connections(conns)

        elif action == "set_owner_user_full_access":
            conns = _get_user_db_connections(include_backend=True)
            try:
                ok = True
                message = 'success'
                for _name, owner_conn, _path in conns:
                    owner_cursor = owner_conn.cursor()
                    create_user_tables(owner_cursor)
                    seed_users_if_needed(owner_cursor)
                    ok, message = set_owner_user_full_access(owner_cursor, body)
                    if not ok:
                        break
                if not ok:
                    for _name, owner_conn, _path in conns:
                        try:
                            owner_conn.rollback()
                        except Exception:
                            pass
                    self._set_headers(400)
                    self.wfile.write(json.dumps({"status": "error", "message": message}).encode())
                else:
                    for _name, owner_conn, _path in conns:
                        owner_conn.commit()
                    self._set_headers()
                    self.wfile.write(json.dumps({"status": "success"}).encode())
            finally:
                _close_user_db_connections(conns)


        elif action == "create_customer":
            ok, message, customer = create_customer(c, body)
            if not ok:
                self._set_headers(400)
                self.wfile.write(json.dumps({"status": "error", "message": message, "customer": customer}).encode())
            else:
                conn.commit()
                self._set_headers()
                self.wfile.write(json.dumps({"status": "success", "customer": customer}).encode())

        elif action == "update_customer":
            ok, message, customer = update_customer(c, body)
            if not ok:
                self._set_headers(400)
                self.wfile.write(json.dumps({"status": "error", "message": message, "customer": customer}).encode())
            else:
                conn.commit()
                self._set_headers()
                self.wfile.write(json.dumps({"status": "success", "customer": customer}).encode())

        elif action == "deactivate_customer":
            ok, message, customer = set_customer_active_status(c, body, False)
            if not ok:
                self._set_headers(400)
                self.wfile.write(json.dumps({"status": "error", "message": message}).encode())
            else:
                conn.commit()
                self._set_headers()
                self.wfile.write(json.dumps({"status": "success", "customer": customer}).encode())

        elif action == "reactivate_customer":
            ok, message, customer = set_customer_active_status(c, body, True)
            if not ok:
                self._set_headers(400)
                self.wfile.write(json.dumps({"status": "error", "message": message}).encode())
            else:
                conn.commit()
                self._set_headers()
                self.wfile.write(json.dumps({"status": "success", "customer": customer}).encode())


        elif action == "update_customer_credit_settings":
            customer_id = handle_credit_settings_sync(c, body)
            conn.commit()
            self._set_headers()
            self.wfile.write(json.dumps({"status": "success", "customer_id": customer_id}).encode())

        elif action == "update_customer_pricing_settings":
            customer_id = handle_customer_pricing_settings_sync(c, body)
            conn.commit()
            self._set_headers()
            self.wfile.write(json.dumps({"status": "success", "customer_id": customer_id}).encode())

        elif action == "upsert_customer_product_price":
            price_id = handle_customer_product_price_sync(c, body)
            conn.commit()
            self._set_headers()
            self.wfile.write(json.dumps({"status": "success", "id": price_id}).encode())

        elif action == "receive_customer_payment":
            payment_id = handle_customer_payment_sync(c, body)
            conn.commit()
            self._set_headers()
            self.wfile.write(json.dumps({"status": "success", "payment_id": payment_id}).encode())

        elif action == "customer_ledger_adjustment":
            customer_id = upsert_customer_from_sync(c, body)
            ledger_id = insert_credit_ledger_entry(c, body, customer_id=customer_id)
            conn.commit()
            self._set_headers()
            self.wfile.write(json.dumps({"status": "success", "ledger_id": ledger_id}).encode())

        elif action == "void_customer_payment":
            ledger_id = handle_customer_payment_void_sync(c, body)
            conn.commit()
            self._set_headers()
            self.wfile.write(json.dumps({"status": "success", "ledger_id": ledger_id}).encode())

        elif action == "add_product":
            ok, message = create_or_update_product(
                c,
                barcode=body.get("barcode", ""),
                name=body.get("name", ""),
                category=body.get("category", "General"),
                cost_price=body.get("cost_price", 0),
                selling_price=body.get("selling_price", body.get("price", 0)),
                wholesale_price=body.get("wholesale_price"),
                sale_price=body.get("sale_price"),
                sale_enabled=body.get("sale_enabled"),
                quantity_type=body.get("quantity_type", "unit"),
                unit_label=body.get("unit_label"),
                opening_stock=body.get("opening_stock", body.get("stock", 0)),
                min_stock_level=body.get("min_stock_level", 0),
                reason=str(body.get("reason", "")).strip(),
            )

            if not ok:
                self._set_headers(400)
                self.wfile.write(json.dumps({"status": "error", "message": message}).encode())
            else:
                conn.commit()
                print(f"  ✅ Product added: {body.get('barcode', '')}")
                self._set_headers()
                self.wfile.write(json.dumps({"status": "success"}).encode())

        elif action == "bulk_import_products":
            rows = body.get("rows", [])
            processed = 0

            for raw_row in rows:
                row = dict(raw_row or {})
                ok, message = create_or_update_product(
                    c,
                    barcode=row.get("barcode", ""),
                    name=row.get("name", ""),
                    category=row.get("category", "General"),
                    cost_price=row.get("cost_price", 0),
                    selling_price=row.get("selling_price", row.get("price", 0)),
                    wholesale_price=row.get("wholesale_price"),
                    sale_price=row.get("sale_price"),
                    sale_enabled=row.get("sale_enabled"),
                    quantity_type=row.get("quantity_type", "unit"),
                    unit_label=row.get("unit_label"),
                    opening_stock=row.get("opening_stock", row.get("stock", 0)),
                    min_stock_level=row.get("min_stock_level", 0),
                    reason="Bulk product import",
                )
                if not ok:
                    self._set_headers(400)
                    self.wfile.write(json.dumps({"status": "error", "message": message}).encode())
                    conn.close()
                    return
                processed += 1

            conn.commit()
            print(f"  ✅ Bulk import: {processed} rows")
            self._set_headers()
            self.wfile.write(json.dumps({"status": "success", "processed": processed}).encode())

        elif action == "edit_product":
            ok, message = create_or_update_product(
                c,
                barcode=body.get("barcode", ""),
                name=body.get("name", ""),
                category=body.get("category", "General"),
                cost_price=body.get("cost_price", 0),
                selling_price=body.get("selling_price", body.get("price", 0)),
                wholesale_price=body.get("wholesale_price"),
                sale_price=body.get("sale_price"),
                sale_enabled=body.get("sale_enabled"),
                quantity_type=body.get("quantity_type", "unit"),
                unit_label=body.get("unit_label"),
                opening_stock=body.get("opening_stock", body.get("stock", 0)),
                min_stock_level=body.get("min_stock_level", 0),
                reason=str(body.get("reason", "")).strip() or "Product updated",
            )

            if not ok:
                self._set_headers(400)
                self.wfile.write(json.dumps({"status": "error", "message": message}).encode())
            else:
                conn.commit()
                print(f"  ✅ Product updated: {body.get('barcode', '')}")
                self._set_headers()
                self.wfile.write(json.dumps({"status": "success"}).encode())

        elif action == "delete_product":
            ok, message = delete_product(
                c,
                barcode=body.get("barcode", ""),
                reason=str(body.get("reason", "")).strip() or "Product removed from inventory",
            )
            if not ok:
                self._set_headers(400)
                self.wfile.write(json.dumps({"status": "error", "message": message}).encode())
            else:
                conn.commit()
                self._set_headers()
                self.wfile.write(json.dumps({"status": "success"}).encode())

        elif action == "update_price":
            barcode = str(body.get("barcode", "")).strip()
            new_price = body.get("new_price", 0)
            price_type = str(body.get("price_type", "selling")).strip().lower()
            sale_enabled = body.get("sale_enabled")
            reason = str(body.get("reason", "")).strip()

            ok, message = update_product_price(
                c,
                barcode=barcode,
                new_price=new_price,
                price_type=price_type,
                sale_enabled=sale_enabled,
                reason=reason,
            )
            if not ok:
                self._set_headers(400)
                self.wfile.write(json.dumps({"status": "error", "message": message}).encode())
            else:
                conn.commit()
                print(f"  ✅ Price updated: {barcode} [{price_type}] → Rs.{parse_float(new_price):.2f}")
                self._set_headers()
                self.wfile.write(json.dumps({"status": "success"}).encode())

        elif action == "add_stock":
            barcode = str(body.get("barcode", "")).strip()
            quantity = body.get("quantity", 0)
            supplier_id = body.get("supplier_id", 0)
            supplier_name = str(body.get("supplier_name", "")).strip()
            cost = body.get("cost", 0)
            reason = str(body.get("reason", "")).strip()

            ok, message, _ = update_stock_receive(
                c,
                barcode=barcode,
                quantity=quantity,
                cost=cost,
                supplier_id=supplier_id,
                supplier_name=supplier_name,
                reason=reason,
            )
            if not ok:
                self._set_headers(400)
                self.wfile.write(json.dumps({"status": "error", "message": message}).encode())
            else:
                conn.commit()
                print(f"  ✅ Stock added: {barcode} +{parse_int(quantity)} units")
                self._set_headers()
                self.wfile.write(json.dumps({"status": "success"}).encode())

        elif action == "adjust_stock":
            barcode = str(body.get("barcode", "")).strip()
            adjustment_type = str(body.get("adjustment_type", "")).strip()
            quantity = body.get("quantity", 0)
            reason = str(body.get("reason", "")).strip()

            ok, message, resulting_stock, stock_delta = update_stock_adjustment(
                c,
                barcode=barcode,
                adjustment_type=adjustment_type,
                quantity=quantity,
                reason=reason,
            )
            if not ok:
                self._set_headers(400)
                self.wfile.write(json.dumps({"status": "error", "message": message}).encode())
            else:
                conn.commit()
                stock_delta_value = stock_delta
                stock_delta = int(stock_delta)
                print(f"  ✅ Stock adjusted: {barcode} {adjustment_type} ({stock_delta:+d})")
                stock_delta = stock_delta_value
                self._set_headers()
                self.wfile.write(
                    json.dumps(
                        {
                            "status": "success",
                            "resulting_stock": resulting_stock,
                            "stock_delta": stock_delta,
                        }
                    ).encode()
                )

        elif action == "update_min_stock":
            barcode = str(body.get("barcode", "")).strip()
            min_stock_level = body.get("min_stock_level", 0)
            reason = str(body.get("reason", "")).strip()

            ok, message = update_min_stock_level(
                c,
                barcode=barcode,
                min_stock_level=min_stock_level,
                reason=reason,
            )
            if not ok:
                self._set_headers(400)
                self.wfile.write(json.dumps({"status": "error", "message": message}).encode())
            else:
                conn.commit()
                print(f"  ✅ Min stock updated: {barcode} → {parse_int(min_stock_level)}")
                self._set_headers()
                self.wfile.write(json.dumps({"status": "success"}).encode())

        else:
            self._set_headers(404)
            self.wfile.write(
                json.dumps({"status": "error", "message": "Unknown action"}).encode()
            )

        conn.close()

    def log_message(self, format, *args):
        print(f"  📡 {args[0]}")


def main():
    init_db()
    port = 8080
    HTTPServer.allow_reuse_address = True
    server = HTTPServer(("0.0.0.0", port), APIHandler)
    print(
        f"""
╔══════════════════════════════════════════════════════════╗
║   🏪 Food City Local API Server                        ║
║                                                          ║
║   Running at: http://localhost:{port}                     ║
║   API URL:    http://localhost:{port}/api/pos_sync.php    ║
║                                                          ║
║   Endpoints:                                             ║
║     GET  ?action=get_products            → Product list  ║
║     GET  ?action=get_sales               → Dashboard     ║
║     GET  ?action=get_owner_dashboard     → Owner home    ║
║     GET  ?action=export_data_backup    → JSON backup   ║
║     GET  ?action=get_business_info       → Business info ║
║     GET  ?action=get_owner_user_summary  → Users counts  ║
║     GET  ?action=get_owner_users         → Users list    ║
║     GET  ?action=get_owner_activity_logs → Activity logs ║
║     POST ?action=owner_login           → Admin login   ║
║     POST ?action=owner_logout          → Admin logout  ║
║     POST ?action=update_business_info   → Save biz info ║
║     POST ?action=create_owner_user      → Add user      ║
║     POST ?action=update_owner_user      → Edit user     ║
║     POST ?action=reset_owner_user_pin   → Reset PIN     ║
║     POST ?action=set_owner_user_active_status → Status  ║
║     POST ?action=set_owner_user_full_access  → Access   ║
║     GET  ?action=get_owner_alerts        → Owner alerts  ║
║     GET  ?action=get_owner_sales_report  → Sales report  ║
║     GET  ?action=get_suppliers           → Suppliers     ║
║     GET  ?action=get_customers           → Customers     ║
║     GET  ?action=get_credit_customers_report → Credit     ║
║     GET  ?action=get_inventory_history   → History       ║
║     POST ?action=pos_sync                → POS sync      ║
║     POST ?action=update_price            → Price update  ║
║     POST ?action=add_stock               → Stock receive ║
║     POST ?action=adjust_stock            → Adjustment    ║
║     POST ?action=update_min_stock        → Min stock     ║
║     POST ?action=bulk_import_products   → Bulk import   ║
║                                                          ║
║   Press Ctrl+C to stop                                   ║
╚══════════════════════════════════════════════════════════╝
"""
    )
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n🛑 Server stopped.")
        server.server_close()


if __name__ == "__main__":
    main()
