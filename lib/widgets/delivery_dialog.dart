import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../database_helper.dart';
import '../providers.dart';

class DeliveryDialog extends ConsumerStatefulWidget {
  final Map<String, dynamic> job;
  final WidgetRef ref;

  const DeliveryDialog({super.key, required this.job, required this.ref});

  @override
  ConsumerState<DeliveryDialog> createState() => _DeliveryDialogState();
}

class _DeliveryDialogState extends ConsumerState<DeliveryDialog> {
  Map<String, int> _deliveredStats = {};
  List<dynamic> _outputItems = [];
  List<Map<String, dynamic>> _pastDeliveries = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final json = jsonDecode(widget.job['items'] ?? "{}");
      _outputItems = json['out'] ?? [];
    } catch (e) {
      _outputItems = [];
    }

    final stats = await DatabaseHelper.instance.getItemDeliveryStats(
      widget.job['id'],
    );
    final deliveries = await DatabaseHelper.instance.getJobDeliveries(
      widget.job['id'],
    );

    if (mounted) {
      setState(() {
        _deliveredStats = stats;
        _pastDeliveries = deliveries;
        _isLoading = false;
      });
    }
  }

  Future<void> _handleDispatch(String itemName, int qty, String date) async {
    await DatabaseHelper.instance.addDelivery(widget.job['id'], itemName, qty, date: date);
    await _loadData();
    widget.ref.invalidate(activeJobsProvider);
  }

  Future<void> _handleEditDeliveryDate(int deliveryId, String newDate) async {
    await DatabaseHelper.instance.updateDeliveryDate(deliveryId, newDate);
    await _loadData();
    widget.ref.invalidate(activeJobsProvider);
  }

  Future<void> _handleDeleteDelivery(int deliveryId) async {
    await DatabaseHelper.instance.deleteDelivery(deliveryId);
    await _loadData();
    widget.ref.invalidate(activeJobsProvider);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 500, maxHeight: 750),
            child: Column(
              children: [
                // --- HEADER ---
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 20, 16, 20),
                  color: const Color(0xFF1A237E),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.local_shipping_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Dispatch Manager",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              "Record outgoing items",
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close, color: Colors.white),
                        tooltip: "Close",
                      ),
                    ],
                  ),
                ),

                // --- CONTENT ---
                Expanded(
                  child: Container(
                    color: Colors.white,
                    child: _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : _outputItems.isEmpty
                        ? _buildEmptyState()
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
                            children: [
                          ..._outputItems.map((item) => Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: _DispatchItemCard(
                              item: item,
                              deliveredCount:
                                  _deliveredStats[item['name']] ?? 0,
                              onDispatch: _handleDispatch,
                            ),
                          )),
                          if (_pastDeliveries.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            const Divider(height: 32),
                            const Row(
                              children: [
                                Icon(
                                  Icons.history_rounded,
                                  size: 18,
                                  color: Color(0xFF1A237E),
                                ),
                                SizedBox(width: 8),
                                Text(
                                  "Dispatch History",
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1A237E),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            ..._pastDeliveries.map((del) => _PastDeliveryCard(
                              delivery: del,
                              onEditDate: _handleEditDeliveryDate,
                              onDelete: _handleDeleteDelivery,
                            )),
                          ],
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inventory_2_outlined, size: 48, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            "No output products defined",
            style: TextStyle(color: Colors.grey[50], fontSize: 16),
          ),
        ],
      ),
    );
  }
}

// --- SEPARATE WIDGET WITH KEEP ALIVE ---
class _DispatchItemCard extends StatefulWidget {
  final dynamic item;
  final int deliveredCount;
  final Function(String, int, String) onDispatch;

  const _DispatchItemCard({
    required this.item,
    required this.deliveredCount,
    required this.onDispatch,
  });

  @override
  State<_DispatchItemCard> createState() => _DispatchItemCardState();
}

class _DispatchItemCardState extends State<_DispatchItemCard>
    with AutomaticKeepAliveClientMixin {
  final TextEditingController _qtyCtrl = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  bool _isSending = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _qtyCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitDispatch(String name, int remaining) async {
    if (_isSending) return;

    int qty = int.tryParse(_qtyCtrl.text) ?? 0;
    if (qty <= 0 || qty > remaining) return;

    FocusScope.of(context).unfocus();
    setState(() => _isSending = true);

    await Future.delayed(const Duration(milliseconds: 400));
    await widget.onDispatch(name, qty, _selectedDate.toIso8601String());

    if (mounted) {
      _qtyCtrl.clear();
      setState(() {
        _isSending = false;
        _selectedDate = DateTime.now();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    String name = widget.item['name'];
    int target = widget.item['qty'];
    int sent = widget.deliveredCount;
    int remaining = target - sent;
    bool isComplete = remaining <= 0;
    double progress = (target > 0) ? (sent / target).clamp(0.0, 1.0) : 0.0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isComplete
              ? Colors.green.withOpacity(0.2)
              : Colors.grey.shade200,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Top Section: Info
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF263238),
                        ),
                      ),
                    ),
                    _StatusBadge(
                      isComplete: isComplete,
                      sent: sent,
                      target: target,
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Visual Progress Bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                    backgroundColor: Colors.grey[100],
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isComplete
                          ? const Color(0xFF43A047)
                          : const Color(0xFF1A237E),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "$sent sent",
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    Text(
                      isComplete ? "Completed" : "$remaining remaining",
                      style: TextStyle(
                        fontSize: 12,
                        color: isComplete
                            ? Colors.green[700]
                            : Colors.orange[800],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Bottom Section: Input (Only if not complete)
          if (!isComplete) ...[
            Container(height: 1, color: Colors.grey[100]),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  // Calendar Picker Button
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _selectedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) {
                        setState(() => _selectedDate = picked);
                      }
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      height: 44,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.calendar_today_rounded,
                            size: 16,
                            color: Color(0xFF1A237E),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            DateFormat('dd MMM').format(_selectedDate),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A237E),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: TextField(
                        controller: _qtyCtrl,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _submitDispatch(
                          name,
                          remaining,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          _MaxLimitFormatter(remaining),
                        ],
                        decoration: InputDecoration(
                          hintText: "Qty (Max $remaining)",
                          hintStyle: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[400],
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.clear, size: 16),
                            onPressed: () => _qtyCtrl.clear(),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 44,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1A237E),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                      onPressed: _isSending
                          ? null
                          : () => _submitDispatch(name, remaining),
                      child: _isSending
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Row(
                              children: [
                                Text(
                                  "SEND",
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                SizedBox(width: 4),
                                Icon(Icons.send_rounded, size: 14),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ] else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8),
              color: Colors.green[50],
              child: const Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle, size: 14, color: Colors.green),
                    SizedBox(width: 6),
                    Text(
                      "Dispatch Complete",
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final bool isComplete;
  final int sent;
  final int target;

  const _StatusBadge({
    required this.isComplete,
    required this.sent,
    required this.target,
  });

  @override
  Widget build(BuildContext context) {
    Color bg = isComplete ? Colors.green[50]! : Colors.orange[50]!;
    Color text = isComplete ? Colors.green[700]! : Colors.orange[800]!;
    String label = isComplete ? "DONE" : "${((sent / target) * 100).toInt()}%";

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: text.withOpacity(0.1)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: text,
          fontWeight: FontWeight.bold,
          fontSize: 10,
        ),
      ),
    );
  }
}

class _MaxLimitFormatter extends TextInputFormatter {
  final int max;
  _MaxLimitFormatter(this.max);

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) return newValue;
    int? val = int.tryParse(newValue.text);
    if (val == null) return oldValue;
    if (val > max) return oldValue;
    return newValue;
  }
}

class _PastDeliveryCard extends StatelessWidget {
  final Map<String, dynamic> delivery;
  final Function(int, String) onEditDate;
  final Function(int) onDelete;

  const _PastDeliveryCard({
    required this.delivery,
    required this.onEditDate,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final int id = delivery['id'];
    final String name = delivery['item_name'] ?? 'Unknown';
    final int qty = delivery['qty_delivered'] ?? 0;
    final String dateStr = delivery['delivery_date'] ?? '';
    final DateTime date = DateTime.tryParse(dateStr) ?? DateTime.now();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.green[50],
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.done_all_rounded, color: Colors.green[700], size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "$name (x$qty)",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Color(0xFF263238),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  DateFormat('dd MMM yyyy, hh:mm a').format(date),
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_calendar_rounded, size: 20, color: Colors.blue),
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: date,
                firstDate: DateTime(2020),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (picked != null) {
                onEditDate(id, picked.toIso8601String());
              }
            },
            tooltip: "Edit Date",
          ),
          IconButton(
            icon: Icon(Icons.delete_outline_rounded, size: 20, color: Colors.red[400]),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text("Delete Shipment?"),
                  content: Text("Are you sure you want to delete this shipment of $qty $name?"),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text("Cancel"),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                      child: const Text("Delete"),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                onDelete(id);
              }
            },
            tooltip: "Delete Shipment",
          ),
        ],
      ),
    );
  }
}
