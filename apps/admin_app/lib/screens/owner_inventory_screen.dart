
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import '../providers/admin_provider.dart';
import 'inventory_history_screen.dart';

class OwnerInventoryScreen extends StatefulWidget {
  const OwnerInventoryScreen({super.key});

  @override
  State<OwnerInventoryScreen> createState() => _OwnerInventoryScreenState();
}

class _OwnerInventoryScreenState extends State<OwnerInventoryScreen> {
  String _search = '';
  String _filter = 'all';

  String _formatMoney(num value) => 'Rs. ${value.toStringAsFixed(2)}';

  List<Product> _filterProducts(List<Product> products) {
    final query = _search.trim().toLowerCase();

    return products.where((product) {
      final matchesSearch =
          query.isEmpty ||
          product.name.toLowerCase().contains(query) ||
          product.barcode.toLowerCase().contains(query);

      final matchesFilter = switch (_filter) {
        'low' => product.stock > 0 &&
            product.stock <= (product.minStockLevel > 0 ? product.minStockLevel : 10),
        'out' => product.stock <= 0,
        _ => true,
      };

      return matchesSearch && matchesFilter;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AdminProvider>();
    final filteredProducts = _filterProducts(provider.products);

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: provider.refreshOwnerDashboard,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            _HeaderCard(
              totalProducts: provider.totalProducts,
              lowStockCount: provider.lowStockCount,
              outOfStockCount: provider.outOfStockCount,
            ),
            const SizedBox(height: 16),
            TextField(
              decoration: InputDecoration(
                hintText: 'Search by product name or barcode',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _search.isNotEmpty
                    ? IconButton(
                        onPressed: () => setState(() => _search = ''),
                        icon: const Icon(Icons.clear),
                      )
                    : null,
              ),
              onChanged: (value) => setState(() => _search = value),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _buildFilterChip('All', 'all'),
                  _buildFilterChip('Low Stock', 'low'),
                  _buildFilterChip('Out of Stock', 'out'),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (provider.isLoading && provider.products.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 120),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (filteredProducts.isEmpty)
              const _EmptyInventoryState()
            else
              ...filteredProducts.map(
                (product) => _ProductTile(
                  product: product,
                  formatMoney: _formatMoney,
                  onTap: () => _showProductActions(context, provider, product),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final selected = _filter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => setState(() => _filter = value),
      ),
    );
  }

  Future<void> _showProductActions(
    BuildContext context,
    AdminProvider provider,
    Product product,
  ) async {
    final minStockController = TextEditingController(
      text: product.minStockLevel.toString(),
    );
    final priceController = TextEditingController(
      text: product.sellingPrice.toStringAsFixed(2),
    );

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 8,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 18,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                product.name,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Barcode: ${product.barcode}',
                style: const TextStyle(
                  color: Color(0xFF667085),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 16),
              _ActionTile(
                icon: Icons.history,
                color: const Color(0xFF0F3D91),
                title: 'View inventory history',
                subtitle: 'Open full movement timeline',
                onTap: () {
                  Navigator.pop(sheetContext);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => InventoryHistoryScreen(product: product),
                    ),
                  );
                },
              ),
              _ActionTile(
                icon: Icons.sell_outlined,
                color: const Color(0xFF147A5A),
                title: 'Update selling price',
                subtitle: 'Keep owner changes lightweight and safe',
                onTap: () async {
                  final ok = await _showPriceEditor(
                    context: context,
                    provider: provider,
                    controller: priceController,
                    product: product,
                  );
                  if (ok && mounted) {
                    Navigator.pop(sheetContext);
                  }
                },
              ),
              _ActionTile(
                icon: Icons.flag_outlined,
                color: const Color(0xFFF79009),
                title: 'Update minimum stock level',
                subtitle: 'Control low-stock alert thresholds',
                onTap: () async {
                  final ok = await _showMinStockEditor(
                    context: context,
                    provider: provider,
                    controller: minStockController,
                    product: product,
                  );
                  if (ok && mounted) {
                    Navigator.pop(sheetContext);
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<bool> _showPriceEditor({
    required BuildContext context,
    required AdminProvider provider,
    required TextEditingController controller,
    required Product product,
  }) async {
    bool success = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Selling Price\n${product.name}'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Selling Price',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final value = double.tryParse(controller.text.trim());
              if (value == null || value <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Enter a valid selling price.'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              final updated = await provider.updateProductPrice(
                product.barcode,
                value,
              );

              if (!context.mounted) return;

              if (updated) {
                success = true;
                Navigator.pop(dialogContext);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Selling price updated.'),
                    backgroundColor: Colors.green,
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Failed to update selling price.'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    return success;
  }

  Future<bool> _showMinStockEditor({
    required BuildContext context,
    required AdminProvider provider,
    required TextEditingController controller,
    required Product product,
  }) async {
    bool success = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Minimum Stock\n${product.name}'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Minimum stock level',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final value = int.tryParse(controller.text.trim());
              if (value == null || value < 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Enter a valid minimum stock level.'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              final updated = await provider.updateMinStockLevel(
                product.barcode,
                value,
              );

              if (!context.mounted) return;

              if (updated) {
                success = true;
                Navigator.pop(dialogContext);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Minimum stock level updated.'),
                    backgroundColor: Colors.green,
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Failed to update minimum stock level.'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    return success;
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.totalProducts,
    required this.lowStockCount,
    required this.outOfStockCount,
  });

  final int totalProducts;
  final int lowStockCount;
  final int outOfStockCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF094067), Color(0xFF3E7CB1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Inventory',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Quick product check for the owner.',
            style: TextStyle(
              color: Colors.white.withOpacity(0.82),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _TopPill(label: 'Products', value: '$totalProducts'),
              const SizedBox(width: 8),
              _TopPill(label: 'Low', value: '$lowStockCount'),
              const SizedBox(width: 8),
              _TopPill(label: 'Out', value: '$outOfStockCount'),
            ],
          ),
        ],
      ),
    );
  }
}

class _TopPill extends StatelessWidget {
  const _TopPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({
    required this.product,
    required this.formatMoney,
    required this.onTap,
  });

  final Product product;
  final String Function(num value) formatMoney;
  final VoidCallback onTap;

  Color get _statusColor {
    if (product.stock <= 0) return const Color(0xFFD92D20);
    if (product.stock <= (product.minStockLevel > 0 ? product.minStockLevel : 10)) {
      return const Color(0xFFF79009);
    }
    return const Color(0xFF12B76A);
  }

  String get _statusText {
    if (product.stock <= 0) return 'Out of Stock';
    if (product.stock <= (product.minStockLevel > 0 ? product.minStockLevel : 10)) {
      return 'Low Stock';
    }
    return 'In Stock';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: const Color(0xFFE7F0FF),
                    child: const Icon(
                      Icons.inventory_2_outlined,
                      color: Color(0xFF0F3D91),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            color: Color(0xFF172433),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Barcode: ${product.barcode}',
                          style: const TextStyle(
                            color: Color(0xFF667085),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.chevron_right,
                    color: Color(0xFF98A2B3),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _InfoChip(
                    label: _statusText,
                    color: _statusColor,
                    background: _statusColor.withOpacity(0.12),
                  ),
                  _InfoChip(
                    label: 'Stock ${product.stock}',
                    color: const Color(0xFF0F3D91),
                    background: const Color(0xFFE7F0FF),
                  ),
                  _InfoChip(
                    label: 'Min ${product.minStockLevel}',
                    color: const Color(0xFF7A5C00),
                    background: const Color(0xFFFFF4D6),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _PriceBox(
                      label: 'Selling',
                      value: formatMoney(product.sellingPrice),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _PriceBox(
                      label: 'Wholesale',
                      value: formatMoney(product.wholesalePrice),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _PriceBox(
                      label: 'Sale',
                      value: product.hasSalePrice
                          ? formatMoney(product.salePrice!)
                          : '—',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.label,
    required this.color,
    required this.background,
  });

  final String label;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _PriceBox extends StatelessWidget {
  const _PriceBox({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE3E9F3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF6B7482),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF172433),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: color.withOpacity(0.12),
        child: Icon(icon, color: color),
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
    );
  }
}

class _EmptyInventoryState extends StatelessWidget {
  const _EmptyInventoryState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 42, horizontal: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
      ),
      child: const Column(
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: 42,
            color: Color(0xFF98A2B3),
          ),
          SizedBox(height: 12),
          Text(
            'No products found',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF172433),
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Try changing the search or filter.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF667085),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
