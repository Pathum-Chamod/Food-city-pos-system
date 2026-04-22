#!/usr/bin/env python3
import argparse, json, sqlite3
from pathlib import Path

def connect(path):
    conn = sqlite3.connect(str(path))
    conn.row_factory = sqlite3.Row
    return conn

def ensure_admin_schema(cur):
    cur.execute("""
    CREATE TABLE IF NOT EXISTS sales (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        total_amount REAL,
        cashier_name TEXT,
        branch TEXT,
        vendor TEXT,
        items TEXT,
        created_at TEXT DEFAULT (datetime('now'))
    )
    """)
    cols = {r[1] for r in cur.execute("PRAGMA table_info(sales)").fetchall()}
    needed = {
        'subtotal_amount': 'subtotal_amount REAL DEFAULT 0',
        'discount_amount': 'discount_amount REAL DEFAULT 0',
        'discount_type': 'discount_type TEXT',
        'payment_method': 'payment_method TEXT',
        'transaction_type': "transaction_type TEXT DEFAULT 'sale'",
        'items_count': 'items_count INTEGER DEFAULT 0',
        'gross_profit': 'gross_profit REAL DEFAULT 0',
    }
    for c, sql in needed.items():
        if c not in cols:
            cur.execute(f"ALTER TABLE sales ADD COLUMN {sql}")

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--pos-db', required=True)
    ap.add_argument('--admin-db', required=True)
    ap.add_argument('--replace', action='store_true', help='Delete backend sales first')
    args = ap.parse_args()

    pos_path = Path(args.pos_db)
    admin_path = Path(args.admin_db)
    if not pos_path.exists():
        raise SystemExit(f'POS DB not found: {pos_path}')
    if not admin_path.exists():
        raise SystemExit(f'Admin DB not found: {admin_path}')

    pos = connect(pos_path)
    admin = connect(admin_path)
    ac = admin.cursor()
    ensure_admin_schema(ac)
    if args.replace:
        ac.execute('DELETE FROM sales')

    sales = pos.execute("SELECT * FROM sales ORDER BY datetime(created_at) ASC, id ASC").fetchall()
    inserted = 0
    for sale in sales:
        sale_id = int(sale['id'])
        items = pos.execute(
            "SELECT barcode, product_name, unit_price, price_category_used, cost_price_snapshot, quantity, base_line_total, item_discount_amount, line_total FROM sale_items WHERE sale_id = ? ORDER BY id ASC",
            (sale_id,),
        ).fetchall()
        payload_items = []
        gross_profit = 0.0
        items_count = 0
        for item in items:
            payload_items.append({
                'product': {
                    'barcode': item['barcode'],
                    'name': item['product_name'],
                    'price': float(item['unit_price'] or 0),
                    'selling_price': float(item['unit_price'] or 0),
                    'cost_price': float(item['cost_price_snapshot'] or 0),
                },
                'quantity': int(item['quantity'] or 0),
                'unit_price_used': float(item['unit_price'] or 0),
                'price_type_used': (item['price_category_used'] or 'selling'),
                'cost_price_snapshot': float(item['cost_price_snapshot'] or 0),
                'base_line_total': float(item['base_line_total'] or 0),
                'item_discount_amount': float(item['item_discount_amount'] or 0),
                'line_total': float(item['line_total'] or 0),
            })
            gross_profit += float(item['line_total'] or 0) - (float(item['cost_price_snapshot'] or 0) * int(item['quantity'] or 0))
            items_count += int(item['quantity'] or 0)
        ac.execute(
            """
            INSERT INTO sales (
                total_amount, subtotal_amount, discount_amount, discount_type,
                payment_method, transaction_type, items_count, gross_profit,
                cashier_name, branch, vendor, items, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                float(sale['total_amount'] or 0),
                float(sale['subtotal_amount'] or 0),
                float(sale['discount_amount'] or 0),
                sale['discount_type'],
                sale['payment_method'],
                sale['transaction_type'],
                items_count,
                gross_profit,
                sale['cashier_name'],
                'Hikkaduwa',
                'Alfasoft',
                json.dumps(payload_items),
                sale['created_at'],
            )
        )
        inserted += 1

    admin.commit()
    print(f'Backfilled {inserted} sales from POS to backend.')

if __name__ == '__main__':
    main()
