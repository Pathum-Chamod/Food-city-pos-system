#!/usr/bin/env python3
"""
Local Mock API Server for Food City POS System
Mimics the Spaceship PHP/MySQL API using local SQLite
Run: python3 local_server.py
Endpoint: http://localhost:8080/api/pos_sync.php
"""

import json
import sqlite3
import os
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs
from datetime import date

DB_PATH = os.path.join(os.path.dirname(__file__), "local_admin.db")

def get_db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn

def init_db():
    conn = get_db()
    c = conn.cursor()

    # Products table
    c.execute('''CREATE TABLE IF NOT EXISTS products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        barcode TEXT UNIQUE,
        name TEXT,
        price REAL,
        stock INTEGER,
        updated_at TEXT DEFAULT (datetime('now'))
    )''')

    # Sales table
    c.execute('''CREATE TABLE IF NOT EXISTS sales (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        total_amount REAL,
        cashier_name TEXT,
        branch TEXT,
        vendor TEXT,
        items TEXT,
        created_at TEXT DEFAULT (datetime('now'))
    )''')

    # Suppliers table
    c.execute('''CREATE TABLE IF NOT EXISTS suppliers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT,
        phone TEXT
    )''')

    # Stock receipts table
    c.execute('''CREATE TABLE IF NOT EXISTS stock_receipts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        barcode TEXT,
        quantity INTEGER,
        supplier_id INTEGER,
        cost REAL,
        created_at TEXT DEFAULT (datetime('now'))
    )''')

    # Seed mock data if empty
    if c.execute("SELECT COUNT(*) FROM products").fetchone()[0] == 0:
        products = [
            ("8901234567890", "Munchee Cream Crackers", 450.00, 100),
            ("8901234567891", "Anchor Milk Powder 1kg", 1890.00, 50),
            ("8901234567892", "Raigam Soya Meat", 320.00, 75),
            ("8901234567893", "Signal Toothpaste", 280.00, 60),
        ]
        for barcode, name, price, stock in products:
            c.execute("INSERT INTO products (barcode, name, price, stock, updated_at) VALUES (?, ?, ?, ?, datetime('now'))",
                      (barcode, name, price, stock))
        print("✅ Seeded 4 mock products")

    if c.execute("SELECT COUNT(*) FROM suppliers").fetchone()[0] == 0:
        suppliers = [
            ("Maliban Distributor", "077-1234567"),
            ("Fonterra Lanka", "077-9876543"),
        ]
        for name, phone in suppliers:
            c.execute("INSERT INTO suppliers (name, phone) VALUES (?, ?)", (name, phone))
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
            today = date.today().isoformat()
            rows = c.execute(
                "SELECT cashier_name, SUM(total_amount) as total_sales, COUNT(id) as transaction_count "
                "FROM sales WHERE DATE(created_at) = ? GROUP BY cashier_name", (today,)
            ).fetchall()

            cashier_sales = [dict(r) for r in rows]
            grand_total = sum(float(r["total_sales"]) for r in rows) if rows else 0

            self._set_headers()
            self.wfile.write(json.dumps({
                "status": "success",
                "grand_total": grand_total,
                "cashier_sales": cashier_sales
            }).encode())

        elif action == "get_suppliers":
            rows = c.execute("SELECT * FROM suppliers").fetchall()
            result = [dict(r) for r in rows]
            self._set_headers()
            self.wfile.write(json.dumps(result).encode())

        else:
            self._set_headers(404)
            self.wfile.write(json.dumps({"status": "error", "message": "Unknown action"}).encode())

        conn.close()

    def do_POST(self):
        parsed = urlparse(self.path)
        params = parse_qs(parsed.query)
        action = params.get("action", [None])[0]

        content_length = int(self.headers.get("Content-Length", 0))
        body = json.loads(self.rfile.read(content_length)) if content_length > 0 else {}

        conn = get_db()
        c = conn.cursor()

        if action == "pos_sync":
            sync_type = body.get("type", "")
            data = body.get("data", {})

            if isinstance(data, str):
                data = json.loads(data)

            if sync_type == "SALE":
                c.execute(
                    "INSERT INTO sales (total_amount, cashier_name, branch, vendor, items, created_at) "
                    "VALUES (?, ?, ?, ?, ?, datetime('now'))",
                    (data.get("total_amount", 0), data.get("cashier", "Unknown"),
                     data.get("branch", ""), data.get("vendor", ""), json.dumps(data.get("items", [])))
                )
                # Deduct stock
                for item in data.get("items", []):
                    product = item.get("product", {})
                    barcode = product.get("barcode", "")
                    qty = item.get("quantity", 0)
                    if barcode:
                        c.execute("UPDATE products SET stock = stock - ? WHERE barcode = ?", (qty, barcode))

                conn.commit()
                print(f"  ✅ SALE synced: Rs.{data.get('total_amount', 0)} by {data.get('cashier', 'Unknown')}")
                self._set_headers()
                self.wfile.write(json.dumps({"status": "success"}).encode())

            elif sync_type == "PRICE_UPDATE":
                barcode = data.get("barcode", "")
                new_price = data.get("new_price", 0)
                c.execute("UPDATE products SET price = ?, updated_at = datetime('now') WHERE barcode = ?",
                          (new_price, barcode))
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
            c.execute("UPDATE products SET price = ?, updated_at = datetime('now') WHERE barcode = ?",
                      (new_price, barcode))
            conn.commit()
            print(f"  ✅ Price updated: {barcode} → Rs.{new_price}")
            self._set_headers()
            self.wfile.write(json.dumps({"status": "success"}).encode())

        elif action == "add_stock":
            barcode = body.get("barcode", "")
            quantity = body.get("quantity", 0)
            supplier_id = body.get("supplier_id", 0)
            cost = body.get("cost", 0)

            c.execute("INSERT INTO stock_receipts (barcode, quantity, supplier_id, cost) VALUES (?, ?, ?, ?)",
                      (barcode, quantity, supplier_id, cost))
            c.execute("UPDATE products SET stock = stock + ?, updated_at = datetime('now') WHERE barcode = ?",
                      (quantity, barcode))
            conn.commit()
            print(f"  ✅ Stock added: {barcode} +{quantity} units")
            self._set_headers()
            self.wfile.write(json.dumps({"status": "success"}).encode())

        else:
            self._set_headers(404)
            self.wfile.write(json.dumps({"status": "error", "message": "Unknown action"}).encode())

        conn.close()

    def log_message(self, format, *args):
        # Custom log format
        print(f"  📡 {args[0]}")


def main():
    init_db()
    port = 8080
    HTTPServer.allow_reuse_address = True
    server = HTTPServer(("0.0.0.0", port), APIHandler)
    print(f"""
╔══════════════════════════════════════════════════════════╗
║   🏪 Food City Local API Server                        ║
║                                                          ║
║   Running at: http://localhost:{port}                     ║
║   API URL:    http://localhost:{port}/api/pos_sync.php    ║
║                                                          ║
║   Endpoints:                                             ║
║     GET  ?action=get_products   → Product catalog        ║
║     GET  ?action=get_sales      → Today's sales stats    ║
║     GET  ?action=get_suppliers  → Supplier list          ║
║     POST ?action=pos_sync       → Sync POS transactions  ║
║     POST ?action=update_price   → Update product price   ║
║     POST ?action=add_stock      → Receive stock          ║
║                                                          ║
║   Press Ctrl+C to stop                                   ║
╚══════════════════════════════════════════════════════════╝
""")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n🛑 Server stopped.")
        server.server_close()

if __name__ == "__main__":
    main()
