import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../database_helper.dart';

class AiAuditorService {
  // Read API Key from environment or SharedPreferences (never hardcode in version control)
  static const String _envApiKey = String.fromEnvironment('GEMINI_API_KEY');

  static Future<String?> _getApiKey() async {
    if (_envApiKey.isNotEmpty) return _envApiKey;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('gemini_api_key');
  }

  /// Scans the database and returns a human-readable AI alert message and associated IDs if an anomaly is found.
  /// Returns null if no anomalies are found.
  static Future<Map<String, dynamic>?> runAudit() async {
    try {
      final db = await DatabaseHelper.instance.database;

      // 1. Check for negative balances
      // Balance = total_cost - discount - scrap_value - advance_paid - sum(payments)
      final negativeBalanceQuery = '''
        SELECT j.id, j.bill_no, j.client_name, j.created_at, j.total_cost, j.discount, j.scrap_value, j.advance_paid,
               (SELECT SUM(amount) FROM payments WHERE job_id = j.id) as paid_sum
        FROM jobs j
        WHERE (
          IFNULL(j.total_cost, 0) 
          - IFNULL(j.discount, 0) 
          - IFNULL(j.scrap_value, 0) 
          - IFNULL(j.advance_paid, 0) 
          - IFNULL((SELECT SUM(amount) FROM payments WHERE job_id = j.id), 0)
        ) < 0
        LIMIT 1
      ''';

      final negativeBalances = await db.rawQuery(negativeBalanceQuery);
      if (negativeBalances.isNotEmpty) {
        final row = negativeBalances.first;
        final anomalyData =
            "Bill No: ${row['bill_no'] ?? row['id']}, Client: ${row['client_name']}, Date: ${row['created_at']}, "
            "Total Cost: ${row['total_cost']}, Discount: ${row['discount']}, "
            "Scrap: ${row['scrap_value']}, Advance: ${row['advance_paid']}, "
            "Payments Sum: ${row['paid_sum']}";
        final msg = await _analyzeWithGemini(
          anomalyData,
          defaultMessage:
              "Payment total exceeds the final cost for Bill #${row['bill_no'] ?? row['id']} (${row['client_name']}). Please review payments and discounts.",
        );
        if (msg != null) {
          return {
            'message': msg,
            'job_id': row['id'],
            'client_name': row['client_name'],
            'created_at': row['created_at'],
            'type': 'job',
          };
        }
      }

      // 2. Check for missing locked_daily_wage in attendance
      final missingWageQuery = '''
        SELECT worker_id, date, locked_daily_wage 
        FROM worker_attendance 
        WHERE locked_daily_wage IS NULL OR locked_daily_wage = 0.0 
        LIMIT 1
      ''';
      final missingWages = await db.rawQuery(missingWageQuery);
      if (missingWages.isNotEmpty) {
        final row = missingWages.first;
        final anomalyData =
            "Worker ID: ${row['worker_id']}, Date: ${row['date']}, "
            "Locked Daily Wage: ${row['locked_daily_wage']}";
        final msg = await _analyzeWithGemini(
          anomalyData,
          defaultMessage:
              "Payment total exceeds the final cost for Bill #${row['bill_no'] ?? row['id']} (${row['client_name']}). Please review payments and discounts.",
        );
        if (msg != null) {
          return {
            'message': msg,
            'worker_id': row['worker_id'],
            'date': row['date'],
            'type': 'worker',
          };
        }
      }

      return null; // No anomalies found
    } catch (e) {
      print("Error running AI Audit: $e");
      return null;
    }
  }

  static Future<String?> _analyzeWithGemini(String anomalyData, {String? defaultMessage}) async {
    final apiKey = await _getApiKey();
    if (apiKey == null || apiKey.trim().isEmpty) {
      return defaultMessage ?? "Anomaly detected in record: $anomalyData. Please verify details.";
    }

    try {
      final apiUrl =
          'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$apiKey';
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "contents": [
            {
              "parts": [
                {
                  "text":
                      "You are a read-only database auditor. Look at this anomalous data row: [$anomalyData]. In one short, friendly sentence, tell the admin what looks wrong and suggest they review it. Do not write code.",
                },
              ],
            },
          ],
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['candidates'] != null &&
            data['candidates'].isNotEmpty &&
            data['candidates'][0]['content'] != null &&
            data['candidates'][0]['content']['parts'] != null &&
            data['candidates'][0]['content']['parts'].isNotEmpty) {
          return data['candidates'][0]['content']['parts'][0]['text']
              ?.toString()
              .trim();
        }
      } else {
        print("Gemini API Error: ${response.statusCode} - ${response.body}");
      }
    } catch (e) {
      print("HTTP Request Error: $e");
    }
    return defaultMessage ?? "Anomaly detected. Please review this record.";
  }
}
