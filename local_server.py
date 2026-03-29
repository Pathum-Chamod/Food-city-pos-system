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

    log_inventory_history(
        cursor,
        barcode=barcode,
        movement_type="product_created",
        quantity=0,
        reason=reason or "Product added to inventory",
        reference_type="product_create",
        reference_id=None,
    )

    if opening_stock > 0:
        log_inventory_history(
            cursor,
            barcode=barcode,
            movement_type="stock_receive",
            quantity=opening_stock,
            reason="Opening stock added during product creation",
            reference_type="product_create",
            reference_id=None,
        )

    return True, "success"

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
║     GET  ?action=get_suppliers           → Suppliers     ║
║     GET  ?action=get_inventory_history   → History       ║
║     POST ?action=pos_sync                → POS sync      ║
║     POST ?action=update_price            → Price update  ║
║     POST ?action=add_stock               → Stock receive ║
║     POST ?action=adjust_stock            → Adjustment    ║
║     POST ?action=update_min_stock        → Min stock     ║
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
