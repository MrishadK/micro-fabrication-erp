import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../database_helper.dart';
import '../providers.dart';
import 'excess_payment_dialog.dart';

class PaymentDialog extends StatefulWidget {
  final Map<String, dynamic> job;
  final WidgetRef ref;

  const PaymentDialog({super.key, required this.job, required this.ref});

  @override
  State<PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<PaymentDialog> {
  final _payCtrl = TextEditingController();
  final _scrapCtrl = TextEditingController();
  final _discountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  DateTime _selectedDate = DateTime.now();
  bool _isSaving = false;
  double _total = 0;
  double _alreadyPaid = 0;

  // Track existing deductions so we don't accidentally wipe them
  double _existingDiscount = 0;
  double _existingScrap = 0;

  final Color _primaryColor = const Color(0xFF1A237E);

  @override
  void initState() {
    super.initState();
    _total = (widget.job['total_cost'] as num?)?.toDouble() ?? 0;
    _alreadyPaid = (widget.job['paid_sum'] as num?)?.toDouble() ?? 0;

    // Load existing deductions
    _existingDiscount = (widget.job['discount'] as num?)?.toDouble() ?? 0;
    _existingScrap = (widget.job['scrap_value'] as num?)?.toDouble() ?? 0;

    _noteCtrl.text = _alreadyPaid == 0 ? "Advance" : "Payment";
  }

  @override
  void dispose() {
    _payCtrl.dispose();
    _scrapCtrl.dispose();
    _discountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  // The balance remaining BEFORE any new inputs are applied
  double get _currentBalance =>
      _total - _alreadyPaid - _existingDiscount - _existingScrap;

  // The balance remaining AFTER calculating what they just typed
  double get _newBalance {
    double p = double.tryParse(_payCtrl.text) ?? 0;
    double s = double.tryParse(_scrapCtrl.text) ?? 0;
    double d = double.tryParse(_discountCtrl.text) ?? 0;
    return _currentBalance - (p + s + d);
  }

  void _updateUI() => setState(() {});

  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(1999),
      lastDate: DateTime(2101),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: _primaryColor,
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      int jobId = widget.job['id'];
      double p = double.tryParse(_payCtrl.text) ?? 0;
      double s = double.tryParse(_scrapCtrl.text) ?? 0;
      double d = double.tryParse(_discountCtrl.text) ?? 0;

      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
      String mainNote = _noteCtrl.text.trim();
      if (mainNote.isEmpty) mainNote = "Payment";

      // Calculate excess
      double newDeductions = s + d;
      double excess = (p + newDeductions) - _currentBalance;

      double amountToSaveOnCurrent = p;
      if (excess > 0 && p > 0) {
        // Show dialog
        final appliedAmount = await showDialog<double>(
          context: context,
          builder: (ctx) => ExcessPaymentDialog(
            currentJob: widget.job,
            excessAmount: excess,
            ref: widget.ref,
          ),
        );
        
        if (appliedAmount != null && appliedAmount > 0) {
          amountToSaveOnCurrent = p - appliedAmount;
        }
      }

      // 1. Save Cash Payment to the Ledger
      if (amountToSaveOnCurrent > 0) {
        await DatabaseHelper.instance.addPayment(
          jobId,
          amountToSaveOnCurrent,
          mainNote,
          date: dateStr,
        );
      }

      // 🔥 2. FIX: UPDATE THE JOB RECORD DIRECTLY WITH DEDUCTIONS 🔥
      if (s > 0 || d > 0) {
        // We add the newly typed deductions to the already existing ones
        double updatedDiscount = _existingDiscount + d;
        double updatedScrap = _existingScrap + s;

        final db = await DatabaseHelper.instance.database;
        await db.update(
          'jobs',
          {'discount': updatedDiscount, 'scrap_value': updatedScrap},
          where: 'id = ?',
          whereArgs: [jobId],
        );
        
        // Insert a 0-amount timestamped ledger log so Business Summary can track the exact date
        if (s > 0) {
          await DatabaseHelper.instance.addPayment(jobId, 0, "Scrap Deducted: $s", date: dateStr);
        }
        if (d > 0) {
          await DatabaseHelper.instance.addPayment(jobId, 0, "Discount Given: $d", date: dateStr);
        }
      }

      await Future.delayed(const Duration(milliseconds: 200));

      widget.ref.refresh(activeJobsProvider);
      widget.ref.read(dbRefreshTriggerProvider.notifier).state++;

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error saving payment: $e")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              // --- Header Icon & Title ---
              Center(
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _primaryColor.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.account_balance_wallet_rounded,
                        color: _primaryColor,
                        size: 32,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      "Register Payment",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: _primaryColor,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // --- Current Balance Card ---
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.blue[100]!),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Current Balance",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[800],
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      "₹${_currentBalance.toStringAsFixed(0)}",
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 20,
                        color: Colors.blue[900],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // --- DATE PICKER ---
              Text(
                "Payment Date",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 6),
              InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        DateFormat('dd MMM yyyy').format(_selectedDate),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      Icon(
                        Icons.calendar_month_rounded,
                        color: _primaryColor,
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // --- MAIN PAYMENT INPUT ---
              _buildInputField(
                controller: _payCtrl,
                label: "Cash Received Now",
                icon: Icons.payments_rounded,
                iconColor: Colors.green,
              ),
              const SizedBox(height: 10),

              // --- NOTE & QUICK CHIPS ---
              TextField(
                controller: _noteCtrl,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                decoration: InputDecoration(
                  hintText: "e.g. Second Advance, Full Settlement...",
                  hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
                  prefixIcon: Icon(
                    Icons.edit_note_rounded,
                    color: Colors.grey[500],
                    size: 20,
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: _primaryColor, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _buildQuickChip("Advance"),
                  _buildQuickChip("Second Advance"),
                  _buildQuickChip("Final Payment"),
                  _buildQuickChip("UPI"),
                ],
              ),

              const SizedBox(height: 24),
              Divider(color: Colors.grey[200], thickness: 2),
              const SizedBox(height: 16),

              // --- SECONDARY DEDUCTIONS ---
              _buildInputField(
                controller: _scrapCtrl,
                label: "Add Scrap Value Deduction",
                icon: Icons.recycling_rounded,
                iconColor: Colors.orange,
              ),
              const SizedBox(height: 16),
              _buildInputField(
                controller: _discountCtrl,
                label: "Add Discount Given",
                icon: Icons.money_off_rounded,
                iconColor: Colors.purple,
                isLast: true,
              ),

              const SizedBox(height: 24),
              Divider(color: Colors.grey[200], thickness: 2),
              const SizedBox(height: 16),

              // --- New Balance ---
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "New Balance",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.grey[800],
                    ),
                  ),
                  Text(
                    "₹${_newBalance.toStringAsFixed(0)}",
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 24,
                      color: _newBalance > 0
                          ? Colors.red[600]
                          : Colors.green[600],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 30),

              // --- Action Buttons ---
              Row(
                children: [
                  Expanded(
                    flex: 1,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        side: BorderSide(color: Colors.grey[300]!),
                      ),
                      child: const Text(
                        "Cancel",
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 1,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text(
                              "CONFIRM",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

  Widget _buildQuickChip(String label) {
    return ActionChip(
      label: Text(
        label,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
      ),
      backgroundColor: Colors.indigo[50],
      side: BorderSide(color: Colors.indigo[100]!),
      padding: const EdgeInsets.all(2),
      onPressed: () {
        setState(() {
          _noteCtrl.text = label;
        });
      },
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required Color iconColor,
    bool isLast = false,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: isLast ? TextInputAction.done : TextInputAction.next,
      onChanged: (v) => _updateUI(),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.grey[600], fontSize: 14),
        prefixIcon: Icon(icon, color: iconColor),
        prefixText: "₹ ",
        prefixStyle: const TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.black87,
        ),
        filled: true,
        fillColor: Colors.grey[50],
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        focusedBorder:
            BorderSide(color: _primaryColor, width: 1.5).runtimeType ==
                BorderSide
            ? OutlineInputBorder(
                borderRadius: const BorderRadius.all(Radius.circular(12)),
                borderSide: BorderSide(color: _primaryColor, width: 1.5),
              )
            : null,
      ),
    );
  }
}
