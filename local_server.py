#!/usr/bin/env python3
"""
Local Mock API Server for Food City POS System
Upgraded to support advanced product pricing + inventory sync.
Run: python local_server.py
Endpoint: http://localhost:8080/api/pos_sync.php
"""

import json
import os
import sqlite3
from datetime import datetime, timedelta
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs, urlparse

DB_PATH = os.path.join(os.path.dirname(__file__), "local_admin.db")
POS_DB_PATH = os.path.join(os.path.dirname(__file__), "apps", "pos_app", ".dart_tool", "sqflite_common_ffi", "databases", "food_city_pos.db")


def get_pos_db():
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


def now_sql():
    return "datetime('now','localtime')"


def get_product_row(cursor, barcode):
    return cursor.execute(
        """
        SELECT
            id,
            barcode,
            name,
            COALESCE(category, 'General') AS category,
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
                created_at or datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
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

    quantity = parse_int(quantity, 0)
    if quantity <= 0:
        return False, "Quantity must be greater than 0", None

    cost = parse_float(cost, 0)
    product_name = str(row["name"] or "Unknown product")
    stock_before = parse_int(row["stock"], 0)
    stock_after = stock_before + quantity

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
        (barcode, quantity, parse_int(supplier_id, 0), cost),
    )
    receipt_id = cursor.lastrowid

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

    current_stock = parse_int(row["stock"], 0)
    product_name = str(row["name"] or "Unknown product")
    normalized = str(adjustment_type or "").strip().lower()
    quantity = parse_int(quantity, 0)

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
        stock_delta = quantity - current_stock
        movement_type = "stock_adjust_set"
    else:
        return False, "Invalid adjustment type", None, None

    resulting_stock = current_stock + stock_delta
    if resulting_stock < 0:
        return False, "Resulting stock cannot be negative", None, None
    if stock_delta == 0:
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



def _money_changed(old_value, new_value):
    return round(parse_float(old_value, 0.0), 2) != round(parse_float(new_value, 0.0), 2)


def _normalize_reason_text(reason):
    return str(reason or "").strip().lower()


def _is_generic_product_update_reason(reason):
    normalized = _normalize_reason_text(reason)
    return normalized in {
        "",
        "product updated",
        "updated product",
        "product details updated",
        "updated product details",
    }


def _build_product_update_reason(
    existing_row,
    *,
    name,
    category,
    cost_price,
    selling_price,
    wholesale_price,
    sale_price,
    sale_enabled,
    opening_stock,
    min_stock_level,
    fallback_reason="Product updated",
):
    changes = []

    old_name = str(existing_row["name"] or "").strip()
    old_category = str(existing_row["category"] or "General").strip() or "General"
    old_cost = parse_float(existing_row["cost_price"], 0.0)
    old_selling = parse_float(existing_row["selling_price"], 0.0)
    old_wholesale = parse_float(existing_row["wholesale_price"], old_selling)
    old_sale_price = None if existing_row["sale_price"] is None else round(parse_float(existing_row["sale_price"], 0.0), 2)
    old_sale_enabled = normalize_bool(existing_row["sale_enabled"], False)
    old_min_stock = parse_int(existing_row["min_stock_level"], 0)
    old_stock = parse_int(existing_row["stock"], 0)

    new_name = str(name or "").strip()
    new_category = str(category or "General").strip() or "General"
    new_cost = round(parse_float(cost_price, 0.0), 2)
    new_selling = round(parse_float(selling_price, 0.0), 2)
    new_wholesale = round(parse_float(wholesale_price, new_selling), 2)
    new_sale_price = None if sale_price in (None, "") else round(parse_float(sale_price, 0.0), 2)
    new_sale_enabled = normalize_bool(sale_enabled, False)
    new_min_stock = parse_int(min_stock_level, 0)
    new_stock = parse_int(opening_stock, 0)

    if old_name != new_name:
        changes.append("name")
    if old_category != new_category:
        changes.append("category")
    if _money_changed(old_cost, new_cost):
        changes.append("cost price")
    if _money_changed(old_selling, new_selling):
        changes.append("selling price")
    if _money_changed(old_wholesale, new_wholesale):
        changes.append("wholesale price")
    if old_sale_price != new_sale_price or old_sale_enabled != new_sale_enabled:
        if new_sale_enabled and new_sale_price is not None:
            changes.append("sale price")
        elif old_sale_price is not None or old_sale_enabled:
            changes.append("sale price")
    if old_min_stock != new_min_stock:
        changes.append("minimum stock level")
    if old_stock != new_stock and not changes:
        changes.append("stock")

    if not changes:
        return fallback_reason

    if len(changes) == 1:
        return f"Updated {changes[0]}"
    if len(changes) == 2:
        return f"Updated {changes[0]} and {changes[1]}"

    return f"Updated {', '.join(changes[:-1])}, and {changes[-1]}"



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
    opening_stock=0,
    min_stock_level=0,
    reason="",
    mirror_to_pos=True,
):
    barcode = str(barcode or "").strip()
    name = str(name or "").strip()
    category = str(category or "General").strip() or "General"

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
                barcode,
                name,
                category,
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
    if existing:
        main_reason = (
            _build_product_update_reason(
                existing,
                name=name,
                category=category,
                cost_price=cost_price,
                selling_price=selling_price,
                wholesale_price=resolved_wholesale,
                sale_price=resolved_sale_price,
                sale_enabled=sale_enabled,
                opening_stock=opening_stock,
                min_stock_level=min_stock_level,
                fallback_reason="Product updated",
            )
            if _is_generic_product_update_reason(reason)
            else str(reason).strip()
        )
    else:
        main_reason = str(reason).strip() or "Product added to inventory"
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
    return parse_int(item.get("quantity", 0), 0)


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

            items_sold += quantity
            product_key = barcode or name

            if product_key not in products:
                products[product_key] = {
                    "barcode": barcode,
                    "product_name": name,
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

    products = fetch_products(cursor)
    out_of_stock = [p for p in products if parse_int(p.get("stock", 0), 0) <= 0]
    low_stock = [
        p
        for p in products
        if parse_int(p.get("stock", 0), 0) > 0
        and parse_int(p.get("stock", 0), 0)
        <= (parse_int(p.get("min_stock_level", 0), 0) or 10)
    ]

    out_of_stock = sorted(out_of_stock, key=lambda item: item["name"])
    low_stock = sorted(low_stock, key=lambda item: item["stock"])

    for product in out_of_stock[:6]:
        alerts.append(
            {
                "type": "out_of_stock",
                "severity": "critical",
                "title": f"{product['name']} is out of stock",
                "subtitle": f"Barcode {product['barcode']} • stock 0",
                "barcode": product["barcode"],
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
        stock = parse_int(product.get("stock", 0), 0)
        min_stock = parse_int(product.get("min_stock_level", 0), 0) or 10
        if stock > 0 and stock <= min_stock:
            best_seller_risk.append((seller, product))

    for seller, product in best_seller_risk[:4]:
        alerts.append(
            {
                "type": "best_seller_low_stock",
                "severity": "warning",
                "title": f"Best seller low in stock: {product['name']}",
                "subtitle": f"Sold {seller['quantity_sold']} recently • stock {product['stock']}",
                "barcode": product["barcode"],
            }
        )

    already_added = {alert.get("barcode") for alert in alerts if alert.get("barcode")}
    for product in low_stock[:6]:
        if product["barcode"] in already_added:
            continue
        alerts.append(
            {
                "type": "low_stock",
                "severity": "warning",
                "title": f"{product['name']} is low in stock",
                "subtitle": f"Barcode {product['barcode']} • stock {product['stock']}",
                "barcode": product["barcode"],
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


def _build_owner_sales_report(cursor, params):
    window = _resolve_sales_report_window(params)
    rows = _sales_rows_between_values(cursor, window["start_sql"], window["end_sql"])
    products = fetch_products(cursor)
    product_by_barcode = {str(p.get("barcode") or ""): p for p in products}

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

    for row in rows:
        transaction_type = str(row["transaction_type"] or "sale").strip().lower()
        total_amount = abs(parse_float(row["total_amount"], 0.0))
        subtotal_amount = abs(parse_float(row["subtotal_amount"], 0.0))
        discount_amount = abs(parse_float(row["discount_amount"], 0.0))
        payment_method = str(row["payment_method"] or "").strip().lower()
        created_at = str(row["created_at"] or "")
        sale_day = created_at[:10]
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
            unit_cost = _extract_item_cost_snapshot(item)
            if unit_cost <= 0:
                unit_cost = parse_float(product_by_barcode.get(barcode, {}).get("cost_price"), 0.0)
            product_key = barcode or name
            bucket = by_product.setdefault(
                product_key,
                {
                    "barcode": barcode,
                    "product_name": name,
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
            cashier_bucket["gross_profit"] -= row_profit
        else:
            gross_profit += row_profit
            day_bucket["gross_profit"] += row_profit
            cashier_bucket["gross_profit"] += row_profit

        day_bucket["net_after_refunds"] = day_bucket["net_sales"] - day_bucket["refund_total"]
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

    cashier_summary = sorted(by_cashier.values(), key=lambda item: (item["net_after_refunds"], item["sale_count"]), reverse=True)
    for row in cashier_summary:
        sales_only = parse_int(row["sale_count"], 0)
        for k in ["gross_sales", "discounts", "net_sales", "refund_total", "net_after_refunds", "gross_profit"]:
            row[k] = round(parse_float(row[k], 0.0), 2)
        row["average_sale"] = round(parse_float(row["net_after_refunds"], 0.0) / sales_only, 2) if sales_only > 0 else 0.0

    top_products = sorted(by_product.values(), key=lambda item: (item["net_sales_after_refunds"], item["quantity_sold"] - item["refunded_quantity"]), reverse=True)[:8]
    for row in top_products:
        row["net_quantity_sold"] = parse_int(row["quantity_sold"], 0) - parse_int(row["refunded_quantity"], 0)
        for k in ["sales_amount", "refund_amount", "net_sales_after_refunds", "net_cost_amount", "estimated_profit"]:
            row[k] = round(parse_float(row[k], 0.0), 2)
        sales_val = parse_float(row["net_sales_after_refunds"], 0.0)
        profit_val = parse_float(row["estimated_profit"], 0.0)
        row["margin_percent"] = round((profit_val / sales_val * 100.0), 1) if sales_val > 0 else 0.0

    sold_map = {str(item.get("barcode") or item.get("product_name") or ""): item for item in by_product.values()}
    slow_movers = []
    for product in products:
        stock = parse_int(product.get("stock", 0), 0)
        if stock <= 0:
            continue
        key = str(product.get("barcode") or product.get("name") or "")
        sold = sold_map.get(key, {})
        qty = max(parse_int(sold.get("net_quantity_sold", sold.get("quantity_sold", 0)), 0), 0)
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
        'products': fetch_products(cursor),
        'suppliers': query_rows('SELECT * FROM suppliers ORDER BY name COLLATE NOCASE ASC'),
        'stock_receipts': query_rows('SELECT * FROM stock_receipts ORDER BY datetime(created_at) DESC, id DESC'),
        'inventory_history': query_rows('SELECT * FROM inventory_history ORDER BY datetime(created_at) DESC, id DESC'),
        'sales': query_rows('SELECT * FROM sales ORDER BY datetime(created_at) DESC, id DESC'),
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
                    qty = int(item.get("quantity", 0))

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

                    current_stock = int(row["stock"])
                    if transaction_type == "sale" and current_stock < qty:
                        self._set_headers(400)
                        self.wfile.write(
                            json.dumps(
                                {
                                    "status": "error",
                                    "message": f"Insufficient backend stock for {barcode}. Available: {current_stock}, requested: {qty}",
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
                items_count = sum(max(_extract_item_quantity(item), 0) for item in items)
                gross_profit = 0.0
                for item in items:
                    quantity = max(_extract_item_quantity(item), 0)
                    barcode = _extract_item_barcode(item)
                    unit_price = max(_extract_item_price(item), 0.0)
                    product_row = get_product_row(c, barcode) if barcode else None
                    unit_cost = parse_float(product_row["cost_price"], 0.0) if product_row else 0.0
                    gross_profit += (unit_price - unit_cost) * quantity

                created_at = str(data.get("created_at", "") or "").strip() or datetime.now().astimezone().isoformat()

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
                        created_at
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
                    ),
                )
                sale_id = c.lastrowid

                for item in items:
                    product = item.get("product", {})
                    barcode = str(product.get("barcode", "")).strip()
                    qty = int(item.get("quantity", 0))

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
                    print(f"  ✅ STOCK_ADJUST: {barcode} {adjustment_type} ({stock_delta:+d})")
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
                print(f"  ✅ Stock adjusted: {barcode} {adjustment_type} ({stock_delta:+d})")
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
