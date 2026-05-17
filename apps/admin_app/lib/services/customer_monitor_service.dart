import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/customer_monitor_models.dart';

class CustomerMonitorService {
  CustomerMonitorService({required this.apiUrl});

  final String apiUrl;

  Future<CustomerDashboard> getDashboard() async {
    final json = await _get({'action': 'get_customer_dashboard'});
    return CustomerDashboard.fromJson(json);
  }

  Future<List<CustomerMonitorRow>> getCustomers({
    String query = '',
    String filter = 'all',
    int limit = 100,
  }) async {
    final json = await _get({
      'action': 'get_customers_monitor',
      'query': query,
      'filter': filter,
      'limit': '$limit',
    });
    final customers = json['customers'];
    if (customers is! List) return const [];
    return customers
        .whereType<Map>()
        .map(
          (item) =>
              CustomerMonitorRow.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList();
  }

  Future<CustomerMonitorProfile> getCustomerProfile(int customerId) async {
    final json = await _get({
      'action': 'get_customer_monitor_profile',
      'customer_id': '$customerId',
    });
    return CustomerMonitorProfile.fromJson(json);
  }

  Future<Map<String, dynamic>> _get(Map<String, String> params) async {
    final uri = Uri.parse(apiUrl).replace(queryParameters: params);
    final response = await http.get(uri).timeout(const Duration(seconds: 12));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Local server returned ${response.statusCode}.');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Unexpected server response.');
    }
    final ok = decoded['success'] == true || decoded['status'] == 'success';
    if (!ok) {
      throw Exception(
        (decoded['message'] ?? 'Customer monitor failed').toString(),
      );
    }
    return decoded;
  }
}
