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
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs, urlparse

DB_PATH = os.path.join(os.path.dirname(__file__), "local_admin.db")


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


def log_inventory_history(
    cursor,
    barcode,
    movement_type,
    quantity,
    reason="",
    reference_type="",
    reference_id=None,
):
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
        VALUES (?, ?, ?, ?, ?, ?, datetime('now','localtime'))
        """,
        (
            barcode,
            movement_type,
            quantity,
            reason,
            reference_type,
            reference_id,
        ),
    )


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

    log_inventory_history(
        cursor,
        barcode=barcode,
        movement_type=f"price_change_{normalized}",
        quantity=0,
        reason=reason or f"{normalized.title()} price updated to Rs.{new_price:.2f}",
        reference_type="price_update",
        reference_id=None,
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

    log_inventory_history(
        cursor,
        barcode=barcode,
        movement_type="stock_in",
        quantity=quantity,
        reason=note,
        reference_type="stock_receipt",
        reference_id=receipt_id,
    )
    return True, "success", receipt_id


def update_stock_adjustment(cursor, barcode, adjustment_type, quantity, reason=""):
    row = get_product_row(cursor, barcode)
    if not row:
        return False, "Product not found", None, None

    current_stock = parse_int(row["stock"], 0)
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

    log_inventory_history(
        cursor,
        barcode=barcode,
        movement_type=movement_type,
        quantity=stock_delta,
        reason=reason or "Manual stock adjustment",
        reference_type="manual_adjustment",
        reference_id=None,
    )
    return True, "success", resulting_stock, stock_delta


def update_min_stock_level(cursor, barcode, min_stock_level, reason=""):
    row = get_product_row(cursor, barcode)
    if not row:
        return False, "Product not found"

    min_stock_level = parse_int(min_stock_level, -1)
    if min_stock_level < 0:
        return False, "Minimum stock level cannot be negative"

    cursor.execute(
        f"""
        UPDATE products
        SET min_stock_level = ?, updated_at = {now_sql()}
        WHERE barcode = ?
        """,
        (min_stock_level, barcode),
    )

    log_inventory_history(
        cursor,
        barcode=barcode,
        movement_type="min_stock_change",
        quantity=0,
        reason=reason or f"Minimum stock level updated to {min_stock_level}",
        reference_type="min_stock_update",
        reference_id=None,
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
    opening_stock=0,
    min_stock_level=0,
    reason="",
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
    log_inventory_history(
        cursor,
        barcode=barcode,
        movement_type=movement_type,
        quantity=0,
        reason=reason or ("Product updated" if existing else "Product added to inventory"),
        reference_type=reference_type,
        reference_id=None,
    )

    if not existing and opening_stock > 0:
        log_inventory_history(
            cursor,
            barcode=barcode,
            movement_type="stock_receive",
            quantity=opening_stock,
            reason="Opening stock added during product creation",
            reference_type="product_create",
            reference_id=None,
        )
    elif existing and previous_stock != opening_stock:
        log_inventory_history(
            cursor,
            barcode=barcode,
            movement_type="product_updated",
            quantity=opening_stock - previous_stock,
            reason="Product stock replaced during update",
            reference_type="product_update",
            reference_id=None,
        )

    return True, "success"


def delete_product(cursor, barcode, reason=""):
    barcode = str(barcode or "").strip()
    if not barcode:
        return False, "Barcode is required"

    row = get_product_row(cursor, barcode)
    if not row:
        return False, "Product not found"

    cursor.execute("DELETE FROM products WHERE barcode = ?", (barcode,))

    log_inventory_history(
        cursor,
        barcode=barcode,
        movement_type="product_deleted",
        quantity=0,
        reason=reason or "Product removed from inventory",
        reference_type="product_delete",
        reference_id=None,
    )
    return True, "success"


def bulk_delete_products(cursor, barcodes, reason=""):
    deleted = 0
    for raw_barcode in barcodes or []:
        barcode = str(raw_barcode or "").strip()
        if not barcode:
            continue
        ok, _ = delete_product(cursor, barcode, reason=reason)
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
                       SUM(total_amount) AS total_sales,
                       COUNT(id) AS transaction_count
                FROM sales
                WHERE DATE(created_at) = DATE('now','localtime')
                GROUP BY cashier_name
                """
            ).fetchall()

            cashier_sales = [dict(r) for r in rows]
            grand_total = sum(float(r["total_sales"]) for r in rows) if rows else 0

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

        if action == "pos_sync":
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

                c.execute(
                    f"""
                    INSERT INTO sales (
                        total_amount,
                        cashier_name,
                        branch,
                        vendor,
                        items,
                        created_at
                    )
                    VALUES (?, ?, ?, ?, ?, {now_sql()})
                    """,
                    (
                        data.get("total_amount", 0),
                        data.get("cashier", "Unknown"),
                        data.get("branch", ""),
                        data.get("vendor", ""),
                        json.dumps(items),
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
║     GET  ?action=get_owner_alerts        → Owner alerts  ║
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
