#!/usr/bin/env python3
"""
Local Mock API Server for Food City POS System
Mimics the Spaceship PHP/MySQL API using local SQLite
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


def log_inventory_history(
    cursor,
    barcode,
    movement_type,
    quantity,
    reason="",
    reference_type="",
    reference_id=None,
):
    """Write one inventory movement record."""
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


def init_db():
    conn = get_db()
    c = conn.cursor()

    # Product master
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

    # Sales summary table
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

    # Suppliers
    c.execute(
        """
        CREATE TABLE IF NOT EXISTS suppliers (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT,
            phone TEXT
        )
        """
    )

    # Stock receipts from suppliers
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

    # Unified inventory history / stock movement table
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

    # Seed mock products if empty
    if c.execute("SELECT COUNT(*) FROM products").fetchone()[0] == 0:
        products = [
            ("4791044000123", "Munchee Super Cream Cracker 500g", 450.00, 100),
            ("4792011001234", "Anchor Milk Powder 400g", 1100.00, 50),
            ("4792022005678", "Saman Halmassa 425g", 650.00, 30),
            ("4793033009999", "Kist Strawberry Jam 500g", 580.00, 40),
        ]
        for barcode, name, price, stock in products:
            c.execute(
                """
                INSERT INTO products (barcode, name, price, stock, updated_at)
                VALUES (?, ?, ?, ?, datetime('now','localtime'))
                """,
                (barcode, name, price, stock),
            )
        print("✅ Seeded 4 mock products")

    # Seed suppliers if empty
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
            rows = c.execute("SELECT * FROM products").fetchall()
            result = [dict(r) for r in rows]
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
            sync_type = body.get("type", "")
            data = body.get("data", {})

            if isinstance(data, str):
                data = json.loads(data)

            if sync_type == "SALE":
                transaction_type = str(data.get("transaction_type", "sale")).lower()
                items = data.get("items", [])

                # Validate all items before writing anything
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

                # Insert sale/refund record
                c.execute(
                    """
                    INSERT INTO sales (
                        total_amount,
                        cashier_name,
                        branch,
                        vendor,
                        items,
                        created_at
                    )
                    VALUES (?, ?, ?, ?, ?, datetime('now','localtime'))
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

                # Apply stock changes + log history
                for item in items:
                    product = item.get("product", {})
                    barcode = str(product.get("barcode", "")).strip()
                    qty = int(item.get("quantity", 0))

                    stock_delta = qty if transaction_type == "refund" else -qty

                    c.execute(
                        """
                        UPDATE products
                        SET stock = stock + ?, updated_at = datetime('now','localtime')
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

            elif sync_type == "PRICE_UPDATE":
                barcode = data.get("barcode", "")
                new_price = data.get("new_price", 0)

                c.execute(
                    """
                    UPDATE products
                    SET price = ?, updated_at = datetime('now','localtime')
                    WHERE barcode = ?
                    """,
                    (new_price, barcode),
                )

                log_inventory_history(
                    c,
                    barcode=barcode,
                    movement_type="price_update",
                    quantity=0,
                    reason=f"Price updated to Rs.{new_price}",
                    reference_type="price_update",
                    reference_id=None,
                )

                conn.commit()
                print(f"  ✅ PRICE_UPDATE: {barcode} → Rs.{new_price}")
                self._set_headers()
                self.wfile.write(json.dumps({"status": "success"}).encode())

            else:
                self._set_headers()
                self.wfile.write(json.dumps({"status": "success"}).encode())

        elif action == "update_price":
            barcode = body.get("barcode", "")
            new_price = body.get("new_price", 0)

            c.execute(
                """
                UPDATE products
                SET price = ?, updated_at = datetime('now','localtime')
                WHERE barcode = ?
                """,
                (new_price, barcode),
            )

            log_inventory_history(
                c,
                barcode=barcode,
                movement_type="price_update",
                quantity=0,
                reason=f"Price updated to Rs.{new_price}",
                reference_type="price_update",
                reference_id=None,
            )

            conn.commit()
            print(f"  ✅ Price updated: {barcode} → Rs.{new_price}")
            self._set_headers()
            self.wfile.write(json.dumps({"status": "success"}).encode())

        elif action == "add_stock":
            barcode = body.get("barcode", "")
            quantity = int(body.get("quantity", 0))
            supplier_id = int(body.get("supplier_id", 0))
            cost = float(body.get("cost", 0))

            c.execute(
                """
                INSERT INTO stock_receipts (
                    barcode,
                    quantity,
                    supplier_id,
                    cost,
                    created_at
                )
                VALUES (?, ?, ?, ?, datetime('now','localtime'))
                """,
                (barcode, quantity, supplier_id, cost),
            )
            receipt_id = c.lastrowid

            c.execute(
                """
                UPDATE products
                SET stock = stock + ?, updated_at = datetime('now','localtime')
                WHERE barcode = ?
                """,
                (quantity, barcode),
            )

            log_inventory_history(
                c,
                barcode=barcode,
                movement_type="stock_in",
                quantity=quantity,
                reason="Received stock from supplier",
                reference_type="stock_receipt",
                reference_id=receipt_id,
            )

            conn.commit()
            print(f"  ✅ Stock added: {barcode} +{quantity} units")
            self._set_headers()
            self.wfile.write(json.dumps({"status": "success"}).encode())

        elif action == "adjust_stock":
            barcode = body.get("barcode", "").strip()
            adjustment_type = body.get("adjustment_type", "").strip()
            quantity = int(body.get("quantity", 0))
            reason = body.get("reason", "").strip()

            row = c.execute(
                "SELECT stock FROM products WHERE barcode = ?",
                (barcode,),
            ).fetchone()

            if not row:
                self._set_headers(404)
                self.wfile.write(
                    json.dumps(
                        {"status": "error", "message": "Product not found"}
                    ).encode()
                )
            else:
                current_stock = int(row["stock"])

                if adjustment_type == "increase":
                    stock_delta = quantity
                elif adjustment_type == "decrease":
                    stock_delta = -quantity
                elif adjustment_type == "set_exact":
                    stock_delta = quantity - current_stock
                else:
                    self._set_headers(400)
                    self.wfile.write(
                        json.dumps(
                            {"status": "error", "message": "Invalid adjustment type"}
                        ).encode()
                    )
                    conn.close()
                    return

                resulting_stock = current_stock + stock_delta

                if resulting_stock < 0:
                    self._set_headers(400)
                    self.wfile.write(
                        json.dumps(
                            {
                                "status": "error",
                                "message": "Resulting stock cannot be negative",
                            }
                        ).encode()
                    )
                elif stock_delta == 0:
                    self._set_headers(400)
                    self.wfile.write(
                        json.dumps(
                            {"status": "error", "message": "No stock change detected"}
                        ).encode()
                    )
                else:
                    c.execute(
                        """
                        UPDATE products
                        SET stock = ?, updated_at = datetime('now','localtime')
                        WHERE barcode = ?
                        """,
                        (resulting_stock, barcode),
                    )

                    log_inventory_history(
                        c,
                        barcode=barcode,
                        movement_type="adjustment",
                        quantity=stock_delta,
                        reason=reason or "Manual stock adjustment",
                        reference_type="manual_adjustment",
                        reference_id=None,
                    )

                    conn.commit()
                    print(
                        f"  ✅ Stock adjusted: {barcode} {adjustment_type} ({stock_delta:+d})"
                    )
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