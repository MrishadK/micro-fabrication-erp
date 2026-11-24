import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../database_helper.dart';
import '../providers.dart';
import 'delivery_dialog.dart';

class JobCard extends StatelessWidget {
  final Map<String, dynamic> job;
  final WidgetRef ref;
  const JobCard({super.key, required this.job, required this.ref});

  @override
  Widget build(BuildContext context) {
    String status = job['status'] ?? 'Nothing';
    Color statusColor = _getStatusColor(status);

    // --- NEW: Calculate Progress ---
    final int targetQty = (job['target_qty'] as int?) ?? 0;
    final int deliveredQty = (job['delivered_sum'] as int?) ?? 0;
    final double progress = targetQty > 0
        ? (deliveredQty / targetQty).clamp(0.0, 1.0)
        : 0.0;
    // -------------------------------

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [const BoxShadow(color: Colors.black12, blurRadius: 4)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  status.toUpperCase(),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                    color: statusColor,
                  ),
                ),
              ),
              Text(
                "#${job['bill_no'] ?? job['id']}",
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Client Info
          Text(
            job['client_name'],
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            job['client_phone'] ?? "",
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),

          const SizedBox(height: 15),

          // --- NEW: VISUAL PROGRESS BAR ---
          if (targetQty > 0 && status != 'Done') ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Dispatch Progress",
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  "$deliveredQty / $targetQty",
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A237E),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: Colors.grey[100],
                valueColor: AlwaysStoppedAnimation<Color>(
                  progress >= 1.0 ? Colors.green : Colors.blue,
                ),
              ),
            ),
            const SizedBox(height: 15),
          ],

          // -------------------------------
          const Spacer(),

          // Status Dropdown
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(5),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: status,
                isExpanded: true,
                items: ['Nothing', 'Ongoing', 'Ready', 'Done'].map((
                  String val,
                ) {
                  return DropdownMenuItem<String>(
                    value: val,
                    child: Text(
                      val,
                      style: TextStyle(color: _getStatusColor(val)),
                    ),
                  );
                }).toList(),
                onChanged: (newVal) async {
                  if (newVal != null) {
                    await DatabaseHelper.instance.updateStatus(
                      job['id'],
                      newVal,
                    );
                    ref.refresh(activeJobsProvider);
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Dispatch Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A237E),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () => showDialog(
                context: context,
                builder: (_) => DeliveryDialog(job: job, ref: ref),
              ),
              icon: const Icon(Icons.local_shipping, size: 16),
              label: const Text("Dispatch / Manage"),
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Ongoing':
        return Colors.blue;
      case 'Ready':
        return Colors.orange;
      case 'Done':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }
}
