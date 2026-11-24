import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../database_helper.dart';

class ExcessPaymentDialog extends StatefulWidget {
  final Map<String, dynamic> currentJob;
  final double excessAmount;
  final WidgetRef ref;

  const ExcessPaymentDialog({
    super.key,
    required this.currentJob,
    required this.excessAmount,
    required this.ref,
  });

  @override
  State<ExcessPaymentDialog> createState() => _ExcessPaymentDialogState();
}

class _ExcessPaymentDialogState extends State<ExcessPaymentDialog> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _unpaidBills = [];
  final Color _primaryColor = const Color(0xFF1A237E);
  
  late double _remainingExcess;
  double _totalApplied = 0.0;

  @override
  void initState() {
    super.initState();
    _remainingExcess = widget.excessAmount;
    _fetchUnpaidBills();
  }

  Future<void> _fetchUnpaidBills() async {
    try {
      final clientName = widget.currentJob['client_name'] ?? '';
      final currentJobId = widget.currentJob['id'] ?? -1;

      final bills = await DatabaseHelper.instance.getClientUnpaidBills(clientName, currentJobId);
      
      // Filter out bills with no due
      final List<Map<String, dynamic>> dueBills = [];
      for (var bill in bills) {
        final double cost = (bill['total_cost'] as num?)?.toDouble() ?? 0;
        final double advance = (bill['advance_paid'] as num?)?.toDouble() ?? 0;
        final double paid = (bill['paid_sum'] as num?)?.toDouble() ?? 0;
        final double discount = (bill['discount'] as num?)?.toDouble() ?? 0;
        final double scrap = (bill['scrap_value'] as num?)?.toDouble() ?? 0;
        final double bal = cost - (advance + paid) - discount - scrap;
        if (bal > 0) {
          dueBills.add({...bill, 'calculated_due': bal});
        }
      }

      setState(() {
        _unpaidBills = dueBills;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _applyExcessToBill(Map<String, dynamic> targetBill) async {
    final double targetDue = targetBill['calculated_due'];
    final double applyAmount = _remainingExcess <= targetDue ? _remainingExcess : targetDue;

    if (applyAmount <= 0) return;

    try {
      await DatabaseHelper.instance.addPayment(
        targetBill['id'],
        applyAmount,
        "Excess from Bill #${widget.currentJob['bill_no']?.toString().isNotEmpty == true ? widget.currentJob['bill_no'] : widget.currentJob['id']}",
      );

      setState(() {
        _totalApplied += applyAmount;
        _remainingExcess -= applyAmount;
        
        targetBill['calculated_due'] -= applyAmount;
        if (targetBill['calculated_due'] <= 0) {
          _unpaidBills.removeWhere((b) => b['id'] == targetBill['id']);
        }
      });

      if (_remainingExcess <= 0 && mounted) {
        Navigator.pop(context, _totalApplied);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error applying excess: $e")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: Colors.white,
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _primaryColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  const Icon(Icons.attach_money_rounded, color: Colors.white, size: 40),
                  const SizedBox(height: 8),
                  Text(
                    "Excess Payment: ₹${_remainingExcess.toStringAsFixed(0)}",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "This amount exceeds the current bill.\nApply to another unpaid bill?",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),

            // Body
            Flexible(
              child: _isLoading
                  ? const Padding(
                      padding: EdgeInsets.all(40),
                      child: CircularProgressIndicator(),
                    )
                  : _unpaidBills.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(40),
                          child: Text(
                            _totalApplied > 0 
                                ? "All other bills are paid." 
                                : "No other unpaid bills found for this client.",
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.grey, fontSize: 16),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          shrinkWrap: true,
                          itemCount: _unpaidBills.length,
                          separatorBuilder: (ctx, i) => const Divider(height: 16),
                          itemBuilder: (ctx, i) {
                            final bill = _unpaidBills[i];
                            final String billNo = bill['bill_no']?.toString().isNotEmpty == true 
                                ? bill['bill_no'].toString() 
                                : bill['id'].toString();
                            final DateTime date = DateTime.tryParse(bill['created_at'] ?? '') ?? DateTime.now();
                            final String dateStr = DateFormat('dd MMM yyyy').format(date);
                            final double due = bill['calculated_due'];

                            return Card(
                              elevation: 0,
                              color: Colors.grey[50],
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(color: Colors.grey[200]!),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          "Bill #$billNo",
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                        Text(
                                          dateStr,
                                          style: TextStyle(
                                            color: Colors.grey[600],
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          "DUE: ₹${due.toStringAsFixed(0)}",
                                          style: TextStyle(
                                            color: Colors.red[700],
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                        ElevatedButton(
                                          onPressed: () => _applyExcessToBill(bill),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: _primaryColor,
                                            foregroundColor: Colors.white,
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                          ),
                                          child: Text(
                                            "APPLY ₹${(_remainingExcess <= due ? _remainingExcess : due).toStringAsFixed(0)}",
                                            style: const TextStyle(fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                      ],
                                    )
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),

            // Footer
            Padding(
              padding: const EdgeInsets.all(16),
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context, _totalApplied),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.grey[800],
                  minimumSize: const Size.fromHeight(48),
                  side: BorderSide(color: Colors.grey[400]!),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  _totalApplied > 0 
                      ? "Done — Keep ₹${_remainingExcess.toStringAsFixed(0)} as Credit"
                      : "Skip — Keep as Credit on Current Bill",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
