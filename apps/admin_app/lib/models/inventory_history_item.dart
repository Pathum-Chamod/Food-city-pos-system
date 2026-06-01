import 'package:flutter/material.dart';

class InventoryHistoryItem {
  final String type;
  final String title;
  final String subtitle;
  final String quantityText;
  final String dateText;
  final IconData icon;
  final Color color;
  final String unitLabel;

  const InventoryHistoryItem({
    required this.type,
    required this.title,
    required this.subtitle,
    required this.quantityText,
    required this.dateText,
    required this.icon,
    required this.color,
    required this.unitLabel,
  });
}