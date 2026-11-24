import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../database_helper.dart';
import 'package:printing/printing.dart';
import '../services/wage_pdf.dart';

// Helper function to safely determine the mode
String _resolveMode(Map<String, dynamic>? data, String defaultWageType) {
  if (data == null) return defaultWageType;
  if (data['mode'] != null) return data['mode'].toString();

  final double p = ((data['pieces'] ?? 0) as num).toDouble();
  final List t = data['tasks'] as List? ?? [];
  if (p > 0 || t.isNotEmpty) return 'piece';

  final double f = ((data['fraction'] ?? 0) as num).toDouble();
  final double ot = ((data['ot'] ?? 0) as num).toDouble();
  if (f > 0 || ot > 0) return 'daily';

  return defaultWageType;
}

class WagesView extends StatefulWidget {
  const WagesView({super.key});

  @override
  State<WagesView> createState() => _WagesViewState();
}

class _WagesViewState extends State<WagesView> {
  List<Map<String, dynamic>> _workers = [];
  Map<int, List<Map<String, dynamic>>> _paymentStatusMap = {};
  Map<int, double> _allTimePaymentsMap = {}; // Tracks overall balance
  bool _isLoading = true;
  bool _showInactive = false;
  String _searchQuery = '';
  final Color _primaryColor = const Color(0xFF1A237E);

  late DateTime _startOfWeek;
  late DateTime _endOfWeek;

  @override
  void initState() {
    super.initState();
    _initWeek();
    _loadData();
  }

  void _initWeek() {
    final now = DateTime.now();
    int daysToSubtract = now.weekday == DateTime.sunday ? 0 : now.weekday;
    _startOfWeek = now.subtract(Duration(days: daysToSubtract));
    _startOfWeek = DateTime(
      _startOfWeek.year,
      _startOfWeek.month,
      _startOfWeek.day,
    );
    _endOfWeek = _startOfWeek.add(const Duration(days: 6));
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final workerData = await DatabaseHelper.instance
          .getWorkersWithAttendance();
      final weekKey = DateFormat('yyyy-MM-dd').format(_startOfWeek);
      final paymentData = await DatabaseHelper.instance.getWeeklyPaymentStatus(
        weekKey,
      );

      // Fetch ALL-TIME payments for every worker to calculate Overall Advance
      final db = await DatabaseHelper.instance.database;
      final allPayRes = await db.rawQuery(
        "SELECT worker_id, SUM(amount) as total FROM worker_payment_history GROUP BY worker_id",
      );
      Map<int, double> tempAllTime = {};
      for (var r in allPayRes) {
        tempAllTime[r['worker_id'] as int] = (r['total'] as num).toDouble();
      }

      if (!mounted) return;

      setState(() {
        _workers = workerData.map((e) => Map<String, dynamic>.from(e)).toList();
        _paymentStatusMap = paymentData;
        _allTimePaymentsMap = tempAllTime;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  void _changeWeek(int offset) {
    setState(() {
      _startOfWeek = _startOfWeek.add(Duration(days: 7 * offset));
      _endOfWeek = _startOfWeek.add(const Duration(days: 6));
    });
    _loadData();
  }

  Future<void> _addOrUpdateWorker(
    Map<String, dynamic> newData, {
    int? index,
  }) async {
    try {
      final existing = index != null ? _workers[index] : null;
      final dbData = {
        'name': newData['name'],
        'rate': newData['rate'],
        'wage_type': newData['wage_type'],
        'piece_items': newData['piece_items'],
        'employee_phone': newData['employee_phone'] ?? '',
        'status': newData['status'] ?? 'Active',
        'ot_type': existing?['ot_type'] ?? 'proportional',
        'ot_val': existing?['ot_val'] ?? 1.0,
      };
      if (index != null) dbData['id'] = _workers[index]['id'];

      await DatabaseHelper.instance.saveWorker(dbData);
      _loadData();
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save worker: $e')));
    }
  }

  Future<void> _showPaymentDialog(
    int workerId,
    double earned,
    List<Map<String, dynamic>> history,
  ) async {
    DateTime now = DateTime.now();
    DateTime selectedDate = now;
    if (now.isBefore(_startOfWeek) ||
        now.isAfter(_endOfWeek.add(const Duration(days: 1)))) {
      selectedDate = DateTime(
        _endOfWeek.year,
        _endOfWeek.month,
        _endOfWeek.day,
        12,
        0,
        0,
      );
    }

    double totalPaidSoFar = history.fold(
      0.0,
      (s, e) => s + (e['amount'] as num).toDouble(),
    );
    double pending = earned - totalPaidSoFar;

    final amtCtrl = TextEditingController(
      text: pending > 0 ? pending.round().toString() : "0", // 🔥 Use .round()
    );

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            double entered = double.tryParse(amtCtrl.text) ?? 0.0;
            double newTotal = totalPaidSoFar + entered;
            double diff = newTotal - earned;

            String statusText;
            Color statusBg;
            Color statusBorder;
            Color statusColor;
            IconData statusIcon;

            if (diff > 0) {
              statusText = "Advance / Overpay: +₹${diff.round()}";
              statusBg = const Color(0xFFFFFBEB);
              statusBorder = const Color(0xFFFDE68A);
              statusColor = const Color(0xFFB45309);
              statusIcon = Icons.trending_up_rounded;
            } else if (diff < 0) {
              statusText = "Still Pending: ₹${diff.abs().round()}";
              statusBg = const Color(0xFFFEF2F2);
              statusBorder = const Color(0xFFFECACA);
              statusColor = const Color(0xFFB91C1C);
              statusIcon = Icons.pending_actions_rounded;
            } else {
              statusText = "Will be Fully Paid";
              statusBg = const Color(0xFFECFDF5);
              statusBorder = const Color(0xFFA7F3D0);
              statusColor = const Color(0xFF047857);
              statusIcon = Icons.check_circle_rounded;
            }

            return Dialog(
              backgroundColor: Colors.transparent,
              elevation: 0,
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 1. Blue/Navy header directly touches top clip (No white outline)
                        Container(
                          width: double.infinity,
                          color: _primaryColor,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 14),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(7),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.payments_rounded,
                                  color: Colors.white,
                                  size: 19,
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text(
                                  'Add Payment',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close_rounded,
                                    color: Colors.white70, size: 20),
                                onPressed: () => Navigator.pop(ctx),
                                tooltip: "Close",
                                splashRadius: 18,
                              ),
                            ],
                          ),
                        ),

                        // 2. White body with modern summary card and clean inputs
                        Flexible(
                          child: Container(
                            color: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 22, vertical: 20),
                            child: SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Earned wage summary card
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 14),
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [
                                          Color(0xFFEFF6FF),
                                          Color(0xFFF8FAFC)
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                          color: const Color(0xFFBFDBFE)),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF3B82F6)
                                                .withOpacity(0.12),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.account_balance_wallet_rounded,
                                            color: Color(0xFF2563EB),
                                            size: 20,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'EARNED THIS WEEK',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.blueGrey[600],
                                                  letterSpacing: 0.5,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              const Text(
                                                'Total Wage for Period',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w500,
                                                  color: Color(0xFF1E293B),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Text(
                                          '₹${earned.round()}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 22,
                                            color: Color(0xFF1D4ED8),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 18),

                                  // Payment history list if available
                                  if (history.isNotEmpty) ...[
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          "PREVIOUS PAYMENTS (${history.length})",
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11,
                                            color: Colors.blueGrey[600],
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                        Text(
                                          "Paid: ₹${totalPaidSoFar.round()}",
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.green[700],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Container(
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF8FAFC),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                            color: Colors.blueGrey.shade100),
                                      ),
                                      child: ListView.separated(
                                        shrinkWrap: true,
                                        physics:
                                            const NeverScrollableScrollPhysics(),
                                        itemCount: history.length,
                                        separatorBuilder: (_, __) => Divider(
                                            height: 1,
                                            color: Colors.blueGrey.shade100),
                                        itemBuilder: (context, index) {
                                          final p = history[index];
                                          return Padding(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 12, vertical: 8),
                                            child: Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.spaceBetween,
                                              children: [
                                                Row(
                                                  children: [
                                                    Icon(
                                                      Icons.event_available_rounded,
                                                      size: 16,
                                                      color:
                                                          Colors.blueGrey[500],
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Text(
                                                      DateFormat('dd MMM yyyy')
                                                          .format(DateTime.parse(
                                                              p['paid_date'])),
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        fontSize: 12,
                                                        color:
                                                            Color(0xFF334155),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                Row(
                                                  children: [
                                                    Text(
                                                      "₹${p['amount']}",
                                                      style: TextStyle(
                                                        color:
                                                            Colors.green[700],
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 13,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    InkWell(
                                                      onTap: () async {
                                                        await DatabaseHelper
                                                            .instance
                                                            .deleteSinglePayment(
                                                                p['id']);
                                                        history.remove(p);
                                                        totalPaidSoFar -=
                                                            p['amount'];
                                                        setDialogState(() {});
                                                      },
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              14),
                                                      child: Padding(
                                                        padding:
                                                            const EdgeInsets.all(
                                                                4.0),
                                                        child: Icon(
                                                          Icons
                                                              .delete_outline_rounded,
                                                          color:
                                                              Colors.red[400],
                                                          size: 16,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                    const SizedBox(height: 18),
                                  ],

                                  Text(
                                    "ADD NEW PAYMENT",
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blueGrey[600],
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 8),

                                  // Date Picker button
                                  InkWell(
                                    onTap: () async {
                                      final picked = await showDatePicker(
                                        context: context,
                                        initialDate: selectedDate,
                                        firstDate: DateTime(2020),
                                        lastDate: DateTime(2101),
                                      );
                                      if (picked != null) {
                                        setDialogState(
                                            () => selectedDate = picked);
                                      }
                                    },
                                    borderRadius: BorderRadius.circular(10),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 12),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF8FAFC),
                                        border: Border.all(
                                            color: Colors.blueGrey.shade200),
                                        borderRadius:
                                            BorderRadius.circular(10),
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.calendar_today_rounded,
                                                color: _primaryColor,
                                                size: 18,
                                              ),
                                              const SizedBox(width: 10),
                                              Text(
                                                DateFormat('dd MMM yyyy')
                                                    .format(selectedDate),
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 14,
                                                  color: Color(0xFF1E293B),
                                                ),
                                              ),
                                            ],
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: Colors.blueGrey
                                                  .withOpacity(0.08),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              "Change",
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.blueGrey[700],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 14),

                                  // Amount TextField
                                  TextField(
                                    controller: amtCtrl,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF0F172A),
                                    ),
                                    decoration: InputDecoration(
                                      labelText: 'Amount Paying Now',
                                      labelStyle: TextStyle(
                                        color: Colors.blueGrey[600],
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      prefixIcon: Container(
                                        width: 44,
                                        alignment: Alignment.center,
                                        child: Text(
                                          '₹',
                                          style: TextStyle(
                                            fontSize: 22,
                                            fontWeight: FontWeight.bold,
                                            color: _primaryColor,
                                          ),
                                        ),
                                      ),
                                      filled: true,
                                      fillColor: const Color(0xFFF8FAFC),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 16, vertical: 14),
                                      border: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(10),
                                        borderSide: BorderSide(
                                            color: Colors.blueGrey.shade200),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(10),
                                        borderSide: BorderSide(
                                            color: Colors.blueGrey.shade200),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(10),
                                        borderSide: BorderSide(
                                            color: _primaryColor, width: 2),
                                      ),
                                    ),
                                    onChanged: (v) => setDialogState(() {}),
                                  ),
                                  const SizedBox(height: 12),

                                  // Status Badge Container
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 9),
                                    decoration: BoxDecoration(
                                      color: statusBg,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: statusBorder),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(statusIcon,
                                            color: statusColor, size: 16),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            statusText,
                                            style: TextStyle(
                                              color: statusColor,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        // 3. Footer actions
                        Container(
                          width: double.infinity,
                          color: const Color(0xFFF8FAFC),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              OutlinedButton(
                                onPressed: () => Navigator.pop(ctx),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.blueGrey[700],
                                  side: BorderSide(
                                      color: Colors.blueGrey.shade300),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 11),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8)),
                                ),
                                child: const Text("Close",
                                    style:
                                        TextStyle(fontWeight: FontWeight.w600)),
                              ),
                              const SizedBox(width: 10),
                              ElevatedButton.icon(
                                onPressed: () async {
                                  double amount =
                                      double.tryParse(amtCtrl.text) ?? 0.0;
                                  if (amount > 0) {
                                    int offset =
                                        selectedDate.weekday == DateTime.sunday
                                            ? 0
                                            : selectedDate.weekday;
                                    DateTime correctWeekStart =
                                        selectedDate.subtract(
                                      Duration(days: offset),
                                    );
                                    String weekKey = DateFormat('yyyy-MM-dd')
                                        .format(correctWeekStart);

                                    await DatabaseHelper.instance
                                        .markWeeklyPayment(
                                      workerId,
                                      weekKey,
                                      amount,
                                      paidDate: selectedDate.toIso8601String(),
                                    );
                                  }
                                  if (context.mounted) Navigator.pop(ctx);
                                  _loadData();
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _primaryColor,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 20, vertical: 11),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8)),
                                  elevation: 1,
                                ),
                                icon: const Icon(Icons.check_rounded, size: 18),
                                label: const Text("Add Payment",
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // 🔥 UPDATED: Independent Normal vs OT calculations 🔥
  double _calculateWeeklyPay(Map<String, dynamic> worker) {
    final defaultWageType = worker['wage_type'] ?? 'daily';
    final attendanceMap = worker['attendance_data'] ?? {};
    double totalPay = 0.0;

    for (int i = 0; i < 7; i++) {
      final day = _startOfWeek.add(Duration(days: i));
      final key = DateFormat('yyyy-MM-dd').format(day);

      if (attendanceMap.containsKey(key)) {
        final d = attendanceMap[key];
        final mode = _resolveMode(d, defaultWageType);
        // Always use locked_daily_wage — it is stamped at log-creation time
        // and is immutable. Fall back to 0.0 (not the live rate) so a
        // misconfigured row contributes zero rather than phantom earnings.
        final dayRate = ((d['locked_daily_wage'] as num?)?.toDouble() ?? 0.0);

        if (mode == 'daily') {
          final normalHours = ((d['fraction'] ?? 0) as num).toDouble() * 8.0;
          final otHours = ((d['ot'] ?? 0) as num).toDouble();
          // Rate/8 for normal, Rate/6 for Overtime
          totalPay +=
              (normalHours * (dayRate / 8.0)) + (otHours * (dayRate / 6.0));
        } else if (mode == 'piece') {
          totalPay += (((d['pieces'] ?? 0) as num).toDouble()) * dayRate;
          final tasks = d['tasks'] as List? ?? [];
          for (var t in tasks) {
            totalPay += (((t['total'] ?? 0) as num).toDouble());
          }
        }
      }
    }
    return totalPay;
  }

  // 🔥 UPDATED: Independent Normal vs OT calculations 🔥
  double _calculateAllTimePay(Map<String, dynamic> worker) {
    final defaultWageType = worker['wage_type'] ?? 'daily';
    final attendanceMap =
        worker['attendance_data'] as Map<String, dynamic>? ?? {};
    double totalPay = 0.0;

    attendanceMap.forEach((key, d) {
      final mode = _resolveMode(d, defaultWageType);
      // Always use locked_daily_wage — immutable, stamped at insert time.
      final dayRate = ((d['locked_daily_wage'] as num?)?.toDouble() ?? 0.0);

      if (mode == 'daily') {
        final normalHours = ((d['fraction'] ?? 0) as num).toDouble() * 8.0;
        final otHours = ((d['ot'] ?? 0) as num).toDouble();
        totalPay +=
            (normalHours * (dayRate / 8.0)) + (otHours * (dayRate / 6.0));
      } else if (mode == 'piece') {
        totalPay += (((d['pieces'] ?? 0) as num).toDouble()) * dayRate;
        final tasks = d['tasks'] as List? ?? [];
        for (var t in tasks)
          totalPay += (((t['total'] ?? 0) as num).toDouble());
      }
    });
    return totalPay;
  }

  double get _weeklyGrandTotal {
    final visible = _showInactive
        ? _workers
        : _workers.where((w) => (w['status'] ?? 'Active') == 'Active').toList();
    return visible.fold(
      0.0,
      (sum, worker) => sum + _calculateWeeklyPay(worker),
    );
  }

  double get _weeklyTotalPaid {
    final visible = _showInactive
        ? _workers
        : _workers.where((w) => (w['status'] ?? 'Active') == 'Active').toList();
    double sum = 0.0;
    for (var w in visible) {
      final historyList = _paymentStatusMap[w['id']] ?? [];
      for (var p in historyList)
        sum += (p['amount'] as num?)?.toDouble() ?? 0.0;
    }
    return sum;
  }

  @override
  Widget build(BuildContext context) {
    final formatCurrency = NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 0,
    );
    final weekLabel =
        '${DateFormat('d MMM').format(_startOfWeek)} - ${DateFormat('d MMM').format(_endOfWeek)}';

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 50, 20, 25),
            decoration: BoxDecoration(
              color: _primaryColor,
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(30),
              ),
              boxShadow: [
                BoxShadow(
                  color: _primaryColor.withOpacity(0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Wage Manager',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 10),
                        // 🔥 NEW BUTTON MOVED TO TOP 🔥
                        InkWell(
                          onTap: () => _showWorkerDialog(context, null),
                          borderRadius: BorderRadius.circular(100),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF6D00),
                              borderRadius: BorderRadius.circular(100),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.add, size: 15, color: Colors.white),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Text(
                              'WEEKLY EARNED',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              formatCurrency.format(_weeklyGrandTotal),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        Container(
                          width: 1,
                          height: 30,
                          color: Colors.white24,
                          margin: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Text(
                              'TOTAL PAID',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              formatCurrency.format(_weeklyTotalPaid),
                              style: const TextStyle(
                                color: Colors.greenAccent,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Container(
                  height: 45,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(25),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.chevron_left,
                          color: Colors.white,
                        ),
                        onPressed: () => _changeWeek(-1),
                      ),
                      Text(
                        weekLabel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.chevron_right,
                          color: Colors.white,
                        ),
                        onPressed: () => _changeWeek(1),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : Builder(
                    builder: (context) {
                      final visibleWorkers = _workers.where((w) {
                        if (!_showInactive &&
                            (w['status'] ?? 'Active') != 'Active')
                          return false;
                        if (_searchQuery.isEmpty) return true;

                        final query = _searchQuery.toLowerCase();
                        final nameMatch = (w['name'] ?? '')
                            .toString()
                            .toLowerCase()
                            .contains(query);
                        final numMatch =
                            w['employee_number']?.toString().contains(query) ??
                            false;
                        return nameMatch || numMatch;
                      }).toList();

                      return Column(
                        children: [
                          // -- Search Bar (Shorebird Safe, no new Icons) --
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
                            child: TextField(
                              onChanged: (val) =>
                                  setState(() => _searchQuery = val),
                              decoration: InputDecoration(
                                hintText: 'Search by Name or ID...',
                                prefixIcon: const Padding(
                                  padding: EdgeInsets.all(12.0),
                                  child: Text(
                                    '🔍',
                                    style: TextStyle(fontSize: 16),
                                  ),
                                ),
                                filled: true,
                                fillColor: Colors.white,
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: 0,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: Colors.grey[300]!,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: Colors.grey[300]!,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          // -- Toggle bar --
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '${visibleWorkers.length} worker(s) shown',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () => setState(
                                    () => _showInactive = !_showInactive,
                                  ),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _showInactive
                                          ? Colors.orange[100]
                                          : Colors.grey[200],
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: _showInactive
                                            ? Colors.orange[400]!
                                            : Colors.grey[400]!,
                                      ),
                                    ),
                                    child: Text(
                                      _showInactive
                                          ? 'HIDE INACTIVE'
                                          : 'SHOW INACTIVE',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: _showInactive
                                            ? Colors.orange[900]
                                            : Colors.grey[700],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // -- Worker list --
                          Expanded(
                            child: visibleWorkers.isEmpty
                                ? Center(
                                    child: Text(
                                      _showInactive
                                          ? 'No workers found'
                                          : 'No active workers',
                                      style: TextStyle(color: Colors.grey[500]),
                                    ),
                                  )
                                : ListView.builder(
                                    padding: const EdgeInsets.all(16),
                                    itemCount: visibleWorkers.length,
                                    itemBuilder: (context, index) {
                                      final worker = visibleWorkers[index];
                                      final workerIndex = _workers.indexOf(
                                        worker,
                                      );
                                      final pay = _calculateWeeklyPay(worker);

                                      final allTimeEarned =
                                          _calculateAllTimePay(worker);
                                      final allTimePaid =
                                          _allTimePaymentsMap[worker['id']] ??
                                          0.0;
                                      final overallBalance =
                                          allTimeEarned - allTimePaid;

                                      final defaultWageType =
                                          worker['wage_type'] ?? 'daily';
                                      double totalNormalHours = 0.0;
                                      double totalOtHours = 0.0;
                                      double totalPieces = 0.0;
                                      int totalTasks = 0;

                                      final data =
                                          worker['attendance_data'] ?? {};
                                      for (int i = 0; i < 7; i++) {
                                        final key = DateFormat('yyyy-MM-dd')
                                            .format(
                                              _startOfWeek.add(
                                                Duration(days: i),
                                              ),
                                            );
                                        if (data.containsKey(key)) {
                                          final d = data[key];
                                          final mode = _resolveMode(
                                            d,
                                            defaultWageType,
                                          );
                                          if (mode == 'daily') {
                                            totalNormalHours +=
                                                ((d['fraction'] ?? 0) as num)
                                                    .toDouble() *
                                                8.0;
                                            totalOtHours +=
                                                ((d['ot'] ?? 0) as num)
                                                    .toDouble();
                                          } else if (mode == 'piece') {
                                            totalPieces +=
                                                (((d['pieces'] ?? 0) as num)
                                                    .toDouble());
                                            totalTasks +=
                                                (d['tasks'] as List?)?.length ??
                                                0;
                                          }
                                        }
                                      }

                                      final List<Map<String, dynamic>>
                                      paymentHistory =
                                          _paymentStatusMap[worker['id']] ?? [];
                                      final double totalPaidForWorker =
                                          paymentHistory.fold(
                                            0.0,
                                            (s, e) =>
                                                s +
                                                (e['amount'] as num).toDouble(),
                                          );
                                      final bool hasPayments =
                                          totalPaidForWorker > 0;
                                      final bool isFullyPaid =
                                          totalPaidForWorker >= pay && pay > 0;

                                      return _buildWorkerTile(
                                        worker,
                                        pay,
                                        defaultWageType,
                                        totalNormalHours + totalOtHours,
                                        totalPieces,
                                        totalTasks,
                                        workerIndex,
                                        hasPayments,
                                        isFullyPaid,
                                        totalPaidForWorker,
                                        paymentHistory,
                                        overallBalance,
                                      );
                                    },
                                  ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkerTile(
    Map<String, dynamic> worker,
    double pay,
    String defaultWageType,
    double totalHours,
    double totalPieces,
    int totalTasks,
    int index,
    bool hasPayments,
    bool isFullyPaid,
    double paidAmount,
    List<Map<String, dynamic>> paymentHistory,
    double overallBalance,
  ) {
    final summaryLabel = defaultWageType == 'daily'
        ? '${totalHours.toStringAsFixed(1)} Hrs (Daily)'
        : '${totalPieces.toInt()} Pcs | $totalTasks Linked Tasks';

    String balText = overallBalance < 0
        ? "Advance: ₹${overallBalance.abs().round()}" // 🔥 Use .round()
        : (overallBalance > 0
              ? "Pending Due: ₹${overallBalance.round()}" // 🔥 Use .round()
              : "All Clear");
    Color balColor = overallBalance < 0
        ? Colors.orange[800]!
        : (overallBalance > 0 ? Colors.red[700]! : Colors.green[700]!);
    Color balBg = overallBalance < 0
        ? Colors.orange[50]!
        : (overallBalance > 0 ? Colors.red[50]! : Colors.green[50]!);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () async {
            Future<void> handleSave(Map<String, dynamic> updated) async {
              try {
                final listData = <Map<String, dynamic>>[];
                (updated['attendance_data'] as Map).forEach((k, v) {
                  listData.add({
                    'date': k,
                    'fraction': v['fraction'],
                    'ot': v['ot'],
                    'pieces': v['pieces'],
                    'tasks': v['tasks'],
                    'mode': v['mode'] ?? worker['wage_type'],
                    // IMMUTABILITY GUARANTEE: Use only the value already stamped
                    // inside _attendanceMap. Never fall back to the live profile
                    // rate — that would re-introduce the same-day leak.
                    'locked_daily_wage':
                        (v['locked_daily_wage'] as num?)?.toDouble() ?? 0.0,
                  });
                });
                await DatabaseHelper.instance.updateWorkerAttendance(
                  updated['id'],
                  listData,
                );
                _loadData();
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to save attendance: $e')),
                  );
                }
              }
            }

            final isDesktop = MediaQuery.of(context).size.width >= 750;
            if (isDesktop) {
              await showDialog(
                context: context,
                barrierDismissible: true,
                builder: (c) => Dialog(
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  shadowColor: Colors.transparent,
                  surfaceTintColor: Colors.transparent,
                  insetPadding: EdgeInsets.symmetric(
                    horizontal: MediaQuery.of(context).size.width > 900
                        ? 40
                        : 16,
                    vertical: 24,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: 880,
                        maxHeight: MediaQuery.of(context).size.height * 0.92,
                      ),
                      child: ExcludeSemantics(
                        child: WorkerDetailScreen(
                          workerData: worker,
                          isDialog: true,
                          onSave: handleSave,
                          onEditProfile: () =>
                              _showWorkerDialog(context, worker, index: index),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            } else {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (c) => WorkerDetailScreen(
                    workerData: worker,
                    isDialog: false,
                    onSave: handleSave,
                    onEditProfile: () =>
                        _showWorkerDialog(context, worker, index: index),
                  ),
                ),
              );
            }
            _loadData();
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: isFullyPaid
                          ? Colors.green[50]
                          : (hasPayments ? Colors.orange[50] : Colors.blue[50]),
                      radius: 24,
                      child: isFullyPaid
                          ? const Icon(Icons.check, color: Colors.green)
                          : Text(
                              worker['name'][0].toUpperCase(),
                              style: TextStyle(
                                color: _primaryColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (worker['employee_number'] != null)
                                      Text(
                                        '${worker['employee_number'].toString().padLeft(3, '0')}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.blueGrey[400],
                                          letterSpacing: 1.2,
                                        ),
                                      ),
                                    Text(
                                      worker['name'],
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // --- Status badge (no icons, no emojis) ---
                              Builder(
                                builder: (_) {
                                  final status =
                                      (worker['status'] ?? 'Active') as String;
                                  Color bgColor;
                                  Color textColor;
                                  if (status == 'Active') {
                                    bgColor = Colors.green[100]!;
                                    textColor = Colors.green[800]!;
                                  } else if (status == 'Vacation') {
                                    bgColor = Colors.blue[100]!;
                                    textColor = Colors.blue[800]!;
                                  } else {
                                    bgColor = Colors.grey[200]!;
                                    textColor = Colors.grey[700]!;
                                  }
                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: bgColor,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      status.toUpperCase(),
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        color: textColor,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                          if ((worker['employee_phone'] ?? '').isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              worker['employee_phone'],
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[500],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                          const SizedBox(height: 4),
                          Text(
                            summaryLabel,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey[700],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '₹${pay.round()}', // 🔥 Use .round()
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: _primaryColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        if (hasPayments)
                          InkWell(
                            onTap: () => _showPaymentDialog(
                              worker['id'],
                              pay,
                              paymentHistory,
                            ),
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: isFullyPaid
                                    ? Colors.green[50]
                                    : Colors.orange[50],
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: isFullyPaid
                                      ? Colors.green[200]!
                                      : Colors.orange[200]!,
                                ),
                              ),
                              child: Text(
                                'PAID ₹${paidAmount.round()}', // 🔥 Use .round()
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: isFullyPaid
                                      ? Colors.green[800]
                                      : Colors.orange[900],
                                ),
                              ),
                            ),
                          )
                        else
                          SizedBox(
                            height: 28,
                            child: ElevatedButton(
                              onPressed: () => _showPaymentDialog(
                                worker['id'],
                                pay,
                                paymentHistory,
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _primaryColor,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                              ),
                              child: const Text(
                                'PAY NOW',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                if (overallBalance != 0) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Divider(height: 1),
                  ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      vertical: 6,
                      horizontal: 10,
                    ),
                    decoration: BoxDecoration(
                      color: balBg,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: balColor.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "Overall Status:",
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[700],
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          balText,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: balColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<Map<String, dynamic>?> _showWorkerDialog(
    BuildContext context,
    Map<String, dynamic>? existing, {
    int? index,
  }) {
    final nameCtrl = TextEditingController(text: existing?['name']);
    final rateCtrl = TextEditingController(
      text: existing?['rate']?.toString() ?? '',
    );
    final phoneCtrl = TextEditingController(
      text: existing?['employee_phone'] ?? '',
    );
    String wageType = existing?['wage_type'] ?? 'daily';
    String status = existing?['status'] ?? 'Active';
    List<dynamic> pieceItems = List.from(existing?['piece_items'] ?? []);

    final pNameCtrl = TextEditingController();
    final pRateCtrl = TextEditingController();

    void adjustRate(StateSetter setDialogState, double delta) {
      final current = double.tryParse(rateCtrl.text) ?? 0.0;
      final updated = (current + delta).clamp(0.0, 99999.0);
      rateCtrl.text = updated.toStringAsFixed(0);
      setDialogState(() {});
    }

    int? autoEmpNum = existing?['employee_number'];
    bool isLoadingEmpNum = existing == null;
    final empNumCtrl = TextEditingController(
      text: autoEmpNum?.toString() ?? '',
    );

    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            if (isLoadingEmpNum) {
              isLoadingEmpNum = false;
              DatabaseHelper.instance.getMaxEmployeeNumber().then((max) {
                if (context.mounted) {
                  setDialogState(() {
                    autoEmpNum = max + 1;
                    empNumCtrl.text = autoEmpNum.toString();
                  });
                }
              });
            }
            return Dialog(
              backgroundColor: Colors.transparent,
              elevation: 0,
              shadowColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Header
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 16,
                        ),
                        color: _primaryColor,
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  existing == null ? '+' : 'W',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                existing == null
                                    ? 'Add Worker Profile'
                                    : 'Edit Profile',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            GestureDetector(
                              onTap: () => Navigator.pop(context),
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  shape: BoxShape.circle,
                                ),
                                child: const Text(
                                  ' ✕ ',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Content
                      Flexible(
                        child: Container(
                          color: Colors.white,
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // --- Employee Number (Editable) ---
                                TextField(
                                  controller: empNumCtrl,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'Employee ID',
                                    prefixText: '# ',
                                    border: OutlineInputBorder(),
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 12,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                // --- Name ---
                                TextField(
                                  controller: nameCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'Full Name',
                                    border: OutlineInputBorder(),
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 12,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                // --- Phone ---
                                TextField(
                                  controller: phoneCtrl,
                                  keyboardType: TextInputType.phone,
                                  decoration: const InputDecoration(
                                    labelText: 'Phone Number (optional)',
                                    border: OutlineInputBorder(),
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 12,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                // --- Status selector ---
                                const Text(
                                  'Status',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    for (final s in [
                                      'Active',
                                      'Vacation',
                                      'Left',
                                    ]) ...[
                                      Expanded(
                                        child: GestureDetector(
                                          onTap: () =>
                                              setDialogState(() => status = s),
                                          child: AnimatedContainer(
                                            duration: const Duration(
                                              milliseconds: 180,
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 10,
                                            ),
                                            decoration: BoxDecoration(
                                              color: status == s
                                                  ? (s == 'Active'
                                                        ? Colors.green[500]
                                                        : s == 'Vacation'
                                                        ? Colors.blue[400]
                                                        : Colors.grey[600])
                                                  : Colors.grey[100],
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              border: Border.all(
                                                color: status == s
                                                    ? (s == 'Active'
                                                          ? Colors.green[500]!
                                                          : s == 'Vacation'
                                                          ? Colors.blue[400]!
                                                          : Colors.grey[600]!)
                                                    : Colors.grey[300]!,
                                              ),
                                            ),
                                            child: Center(
                                              child: Text(
                                                s,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                  color: status == s
                                                      ? Colors.white
                                                      : Colors.black87,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      if (s != 'Left') const SizedBox(width: 8),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 16),
                                // --- Wage type ---
                                Row(
                                  children: [
                                    Expanded(
                                      child: GestureDetector(
                                        onTap: () => setDialogState(
                                          () => wageType = 'daily',
                                        ),
                                        child: AnimatedContainer(
                                          duration: const Duration(
                                            milliseconds: 180,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 10,
                                          ),
                                          decoration: BoxDecoration(
                                            color: wageType == 'daily'
                                                ? _primaryColor
                                                : Colors.grey[100],
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            border: Border.all(
                                              color: wageType == 'daily'
                                                  ? _primaryColor
                                                  : Colors.grey[300]!,
                                            ),
                                          ),
                                          child: Center(
                                            child: Text(
                                              'Daily Wage',
                                              style: TextStyle(
                                                color: wageType == 'daily'
                                                    ? Colors.white
                                                    : Colors.black87,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: GestureDetector(
                                        onTap: () => setDialogState(
                                          () => wageType = 'piece',
                                        ),
                                        child: AnimatedContainer(
                                          duration: const Duration(
                                            milliseconds: 180,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 10,
                                          ),
                                          decoration: BoxDecoration(
                                            color: wageType == 'piece'
                                                ? _primaryColor
                                                : Colors.grey[100],
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            border: Border.all(
                                              color: wageType == 'piece'
                                                  ? _primaryColor
                                                  : Colors.grey[300]!,
                                            ),
                                          ),
                                          child: Center(
                                            child: Text(
                                              'Piece Rate',
                                              style: TextStyle(
                                                color: wageType == 'piece'
                                                    ? Colors.white
                                                    : Colors.black87,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                // --- Rate field with +/- increment buttons ---
                                const Text(
                                  'Daily / Base Rate',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    // Decrement button
                                    GestureDetector(
                                      onTap: () =>
                                          adjustRate(setDialogState, -50),
                                      onLongPress: () =>
                                          adjustRate(setDialogState, -500),
                                      child: Container(
                                        width: 48,
                                        height: 48,
                                        decoration: BoxDecoration(
                                          color: Colors.red[50],
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          border: Border.all(
                                            color: Colors.red[200]!,
                                          ),
                                        ),
                                        child: Center(
                                          child: Text(
                                            '-50',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: Colors.red[700],
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    // Rate text field
                                    Expanded(
                                      child: TextField(
                                        controller: rateCtrl,
                                        keyboardType: TextInputType.number,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        decoration: InputDecoration(
                                          labelText: wageType == 'daily'
                                              ? '8-hr Shift'
                                              : 'Default Rate',
                                          floatingLabelBehavior:
                                              FloatingLabelBehavior.always,
                                          border: const OutlineInputBorder(),
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                horizontal: 12,
                                                vertical: 12,
                                              ),
                                          prefixText: '₹ ',
                                        ),
                                        onChanged: (_) => setDialogState(() {}),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    // Increment button
                                    GestureDetector(
                                      onTap: () =>
                                          adjustRate(setDialogState, 50),
                                      onLongPress: () =>
                                          adjustRate(setDialogState, 500),
                                      child: Container(
                                        width: 48,
                                        height: 48,
                                        decoration: BoxDecoration(
                                          color: Colors.green[50],
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          border: Border.all(
                                            color: Colors.green[200]!,
                                          ),
                                        ),
                                        child: Center(
                                          child: Text(
                                            '+50',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: Colors.green[700],
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                if (wageType == 'piece') ...[
                                  const SizedBox(height: 24),
                                  const Divider(height: 1),
                                  const SizedBox(height: 16),
                                  const Text(
                                    'Define Specific Piece Items',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: Colors.blueGrey,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  const Text(
                                    'Define quick-select items to speed up entry later.',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  ...pieceItems.asMap().entries.map(
                                    (e) => Container(
                                      margin: const EdgeInsets.only(bottom: 6),
                                      clipBehavior: Clip.antiAlias,
                                      decoration: BoxDecoration(
                                        color: Colors.grey[50],
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: Colors.grey[200]!,
                                        ),
                                      ),
                                      child: ListTile(
                                        dense: true,
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 0,
                                            ),
                                        visualDensity: VisualDensity.compact,
                                        title: Text(
                                          e.value['name'],
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                        trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 4,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.green[50],
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                '₹${e.value['rate']}',
                                                style: TextStyle(
                                                  color: Colors.green[700],
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            GestureDetector(
                                              onTap: () => setDialogState(
                                                () =>
                                                    pieceItems.removeAt(e.key),
                                              ),
                                              child: Container(
                                                padding: const EdgeInsets.all(
                                                  4,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: Colors.red[50],
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  ' ✕ ',
                                                  style: TextStyle(
                                                    color: Colors.red[700],
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        flex: 3,
                                        child: TextField(
                                          controller: pNameCtrl,
                                          decoration: const InputDecoration(
                                            hintText: 'Item (e.g. Leveling)',
                                            hintStyle: TextStyle(fontSize: 12),
                                            border: OutlineInputBorder(),
                                            contentPadding:
                                                EdgeInsets.symmetric(
                                                  horizontal: 10,
                                                  vertical: 10,
                                                ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        flex: 2,
                                        child: TextField(
                                          controller: pRateCtrl,
                                          keyboardType: TextInputType.number,
                                          decoration: const InputDecoration(
                                            hintText: 'Rate (₹)',
                                            hintStyle: TextStyle(fontSize: 12),
                                            border: OutlineInputBorder(),
                                            contentPadding:
                                                EdgeInsets.symmetric(
                                                  horizontal: 10,
                                                  vertical: 10,
                                                ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      GestureDetector(
                                        onTap: () {
                                          if (pNameCtrl.text.isNotEmpty &&
                                              pRateCtrl.text.isNotEmpty) {
                                            setDialogState(() {
                                              pieceItems.add({
                                                'name': pNameCtrl.text,
                                                'rate':
                                                    double.tryParse(
                                                      pRateCtrl.text,
                                                    ) ??
                                                    0.0,
                                              });
                                              pNameCtrl.clear();
                                              pRateCtrl.clear();
                                            });
                                          }
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 12,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.green,
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: const Text(
                                            '+',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 18,
                                              height: 1.0,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                                const SizedBox(height: 24),
                                SizedBox(
                                  width: double.infinity,
                                  height: 50,
                                  child: ElevatedButton(
                                    onPressed: () async {
                                      if (nameCtrl.text.trim().isEmpty) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Please enter a valid name for the worker.',
                                            ),
                                            backgroundColor: Colors.red,
                                            behavior: SnackBarBehavior.floating,
                                          ),
                                        );
                                        return;
                                      }

                                      try {
                                        final updatedData = {
                                          'employee_number':
                                              int.tryParse(
                                                empNumCtrl.text.trim(),
                                              ) ??
                                              autoEmpNum,
                                          'name': nameCtrl.text.trim(),
                                          'rate':
                                              double.tryParse(rateCtrl.text) ??
                                              0.0,
                                          'wage_type': wageType,
                                          'piece_items': pieceItems,
                                          'employee_phone': phoneCtrl.text
                                              .trim(),
                                          'status': status,
                                        };
                                        await _addOrUpdateWorker(
                                          updatedData,
                                          index: index,
                                        );
                                        final mergedWorker = existing != null
                                            ? Map<String, dynamic>.from(
                                                existing,
                                              )
                                            : <String, dynamic>{};
                                        mergedWorker.addAll(updatedData);

                                        if (context.mounted) {
                                          Navigator.pop(context, mergedWorker);
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'Worker profile saved successfully!',
                                              ),
                                              backgroundColor: Colors.green,
                                              behavior:
                                                  SnackBarBehavior.floating,
                                            ),
                                          );
                                        }
                                      } catch (e) {
                                        debugPrint('Error saving worker: $e');
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'Failed to save worker profile. Please try again.',
                                              ),
                                              backgroundColor: Colors.red,
                                              behavior:
                                                  SnackBarBehavior.floating,
                                            ),
                                          );
                                        }
                                      }
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _primaryColor,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    child: const Text(
                                      'SAVE PROFILE',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                        letterSpacing: 1.0,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ==========================================
//        WORKER DETAIL & CALENDAR
// ==========================================

class WorkerDetailScreen extends StatefulWidget {
  final Map<String, dynamic> workerData;
  final Function(Map<String, dynamic>) onSave;
  final Future<Map<String, dynamic>?> Function() onEditProfile;
  final bool isDialog;

  const WorkerDetailScreen({
    super.key,
    required this.workerData,
    required this.onSave,
    required this.onEditProfile,
    this.isDialog = false,
  });

  @override
  State<WorkerDetailScreen> createState() => _WorkerDetailScreenState();
}

class _WorkerDetailScreenState extends State<WorkerDetailScreen> {
  late DateTime _currentDate;
  bool _isWeeklyView = true;

  late Map<String, dynamic> _localWorkerData;
  late Map<String, dynamic> _attendanceMap;
  List<Map<String, dynamic>> _currentPaymentHistory = [];
  double _allTimePaid = 0.0;
  final Color _primaryColor = const Color(0xFF1A237E);

  // Cache system: holds the unsaved rate from +/- stepper.
  // null = no draft, use _localWorkerData['rate'] (committed DB value).
  // Set the moment user touches +/-, cleared on Save Changes.
  double? _draftRate;

  @override
  void initState() {
    super.initState();
    _currentDate = DateTime.now();
    _localWorkerData = Map<String, dynamic>.from(widget.workerData);
    _attendanceMap = Map<String, dynamic>.from(
      _localWorkerData['attendance_data'] ?? {},
    );
    _loadPayment();
  }

  Future<void> _loadPayment() async {
    final db = await DatabaseHelper.instance.database;
    final workerId = _localWorkerData['id'];

    final allTimeRes = await db.rawQuery(
      "SELECT SUM(amount) as total FROM worker_payment_history WHERE worker_id = ?",
      [workerId],
    );
    final totalPaid = (allTimeRes.first['total'] as num?)?.toDouble() ?? 0.0;

    if (_isWeeklyView) {
      final offset = _currentDate.weekday == DateTime.sunday
          ? 0
          : _currentDate.weekday;
      final start = _currentDate.subtract(Duration(days: offset));
      final weekKey = DateFormat('yyyy-MM-dd').format(start);

      final paymentData = await DatabaseHelper.instance.getWeeklyPaymentStatus(
        weekKey,
      );
      if (mounted) {
        setState(() {
          _currentPaymentHistory = paymentData[workerId] ?? [];
          _allTimePaid = totalPaid;
        });
      }
    } else {
      final monthStr = DateFormat('yyyy-MM').format(_currentDate);
      final res = await db.rawQuery(
        "SELECT * FROM worker_payment_history WHERE worker_id = ? AND paid_date LIKE ?",
        [workerId, '$monthStr%'],
      );

      if (mounted) {
        setState(() {
          _currentPaymentHistory = List<Map<String, dynamic>>.from(res);
          _allTimePaid = totalPaid;
        });
      }
    }
  }

  void _saveAndPop() {
    final updated = Map<String, dynamic>.from(_localWorkerData);
    updated['attendance_data'] = _attendanceMap;
    widget.onSave(updated);
    Navigator.pop(context);
  }

  Future<void> _launchPhone(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone.trim());
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open phone dialer')),
        );
      }
    }
  }

  Future<void> _showEditProfileSheet() async {
    // Always fetch the next number as a suggestion.
    // If worker already has an ID, pre-fill with their current one (editable).
    // If pending, pre-fill with next available auto-increment.
    final int maxNum = await DatabaseHelper.instance.getMaxEmployeeNumber();
    final int suggestedEmpNum =
        (_localWorkerData['employee_number'] as int?) ?? (maxNum + 1);

    final nameCtrl = TextEditingController(
      text: _localWorkerData['name'] ?? '',
    );
    final rateCtrl = TextEditingController(
      text: (_localWorkerData['rate'] ?? 0).toString(),
    );
    final phoneCtrl = TextEditingController(
      text: _localWorkerData['employee_phone'] ?? '',
    );
    // Always editable — pre-filled with existing ID or next auto-increment.
    final empNumCtrl = TextEditingController(text: suggestedEmpNum.toString());
    String status = _localWorkerData['status'] ?? 'Active';

    void adjustRate(StateSetter setS, double delta) {
      final cur = double.tryParse(rateCtrl.text) ?? 0.0;
      final newVal = (cur + delta).clamp(0, 99999).toDouble();
      rateCtrl.text = newVal.toStringAsFixed(0);
      // Write to the draft cache. _localWorkerData['rate'] (DB value) is
      // NOT touched until the user explicitly presses SAVE CHANGES.
      setState(() => _draftRate = newVal);
      setS(() {});
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 600),
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (_, setS) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle bar
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'EDIT WORKER PROFILE',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 16),
                // --- Employee Number (always editable) ---
                TextField(
                  controller: empNumCtrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Employee ID',
                    prefixText: '# ',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // --- Name field ---
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Full Name',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // --- Phone field ---
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Phone Number',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // --- Status selector ---
                const Text(
                  'Status',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (final s in ['Active', 'Vacation', 'Left']) ...[
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setS(() => status = s),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: status == s
                                  ? (s == 'Active'
                                        ? Colors.green[500]
                                        : s == 'Vacation'
                                        ? Colors.blue[400]
                                        : Colors.grey[600])
                                  : Colors.grey[100],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: status == s
                                    ? (s == 'Active'
                                          ? Colors.green[500]!
                                          : s == 'Vacation'
                                          ? Colors.blue[400]!
                                          : Colors.grey[600]!)
                                    : Colors.grey[300]!,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                s,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: status == s
                                      ? Colors.white
                                      : Colors.grey[700],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (s != 'Left') const SizedBox(width: 8),
                    ],
                  ],
                ),
                const SizedBox(height: 16),

                // --- Rate stepper ---
                const Text(
                  'Daily / Base Rate',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    // -50
                    GestureDetector(
                      onTap: () => adjustRate(setS, -50),
                      onLongPress: () => adjustRate(setS, -500),
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.red[50],
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.red[200]!),
                        ),
                        child: Center(
                          child: Text(
                            '-50',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.red[700],
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: rateCtrl,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                        decoration: const InputDecoration(
                          prefixText: '₹ ',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                        onChanged: (v) {
                          // Sync draft cache as the user types manually.
                          setState(() => _draftRate = double.tryParse(v));
                          setS(() {});
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    // +50
                    GestureDetector(
                      onTap: () => adjustRate(setS, 50),
                      onLongPress: () => adjustRate(setS, 500),
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.green[50],
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.green[200]!),
                        ),
                        child: Center(
                          child: Text(
                            '+50',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.green[700],
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // --- Save button ---
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () async {
                      try {
                        final newName = nameCtrl.text.trim();
                        if (newName.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Please enter a valid name for the worker.',
                              ),
                              backgroundColor: Colors.red,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                          return;
                        }

                        final newRate = double.tryParse(rateCtrl.text) ?? 0.0;
                        final newPhone = phoneCtrl.text.trim();
                        // Employee number: always use what's in the field.
                        // User can change it anytime — just re-save.
                        final int? newEmpNum = int.tryParse(
                          empNumCtrl.text.trim(),
                        );

                        // Persist to DB first to ensure it doesn't fail
                        await DatabaseHelper.instance.saveWorker({
                          ..._localWorkerData,
                          'name': newName,
                          'rate': newRate,
                          'employee_phone': newPhone,
                          'status': status,
                          if (newEmpNum != null) 'employee_number': newEmpNum,
                        });

                        // Commit the draft to the live state, then clear the cache.
                        // From this point forward, _draftRate is null and new
                        // attendance entries will use the newly committed rate.
                        if (mounted) {
                          setState(() {
                            _localWorkerData['name'] = newName;
                            _localWorkerData['rate'] = newRate;
                            _localWorkerData['employee_phone'] = newPhone;
                            _localWorkerData['status'] = status;
                            // Lock the ID in memory the moment it's first saved.
                            if (newEmpNum != null)
                              _localWorkerData['employee_number'] = newEmpNum;
                            _draftRate = null; // Draft promoted → clear cache
                          });

                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Profile updated successfully!'),
                              backgroundColor: Colors.green,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                          Navigator.pop(ctx);
                        }
                      } catch (e) {
                        debugPrint('Error updating profile: $e');
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Failed to update profile. Please try again.',
                              ),
                              backgroundColor: Colors.red,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      }
                    },
                    child: const Text(
                      'SAVE CHANGES',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        letterSpacing: 0.5,
                      ),
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

  void _changePeriod(int offset) {
    setState(() {
      if (_isWeeklyView) {
        _currentDate = _currentDate.add(Duration(days: 7 * offset));
      } else {
        _currentDate = DateTime(
          _currentDate.year,
          _currentDate.month + offset,
          _currentDate.day,
        );
      }
    });
    _loadPayment();
  }

  String get _periodLabel {
    if (_isWeeklyView) {
      final offset = _currentDate.weekday == DateTime.sunday
          ? 0
          : _currentDate.weekday;
      final start = _currentDate.subtract(Duration(days: offset));
      final end = start.add(const Duration(days: 6));
      return '${DateFormat('d MMM').format(start)} - ${DateFormat('d MMM').format(end)}';
    } else {
      return DateFormat('MMMM yyyy').format(_currentDate);
    }
  }

  // Uses locked_daily_wage (immutable, stamped at log time) for display.
  // This means +/- or Save Changes NEVER retroactively re-prices any record.
  double _getPayForDayMap(Map<String, dynamic>? data) {
    if (data == null) return 0.0;
    final defaultWageType = _localWorkerData['wage_type'] ?? 'daily';
    // Always use the locked wage stored in the record, not the live profile rate.
    final dayRate = ((data['locked_daily_wage'] as num?)?.toDouble() ?? 0.0);
    final mode = _resolveMode(data, defaultWageType);
    double pay = 0.0;

    if (mode == 'daily') {
      final normalHours = ((data['fraction'] ?? 0) as num).toDouble() * 8.0;
      final otHours = ((data['ot'] ?? 0) as num).toDouble();
      pay += (normalHours * (dayRate / 8.0)) + (otHours * (dayRate / 6.0));
    } else if (mode == 'piece') {
      pay += (((data['pieces'] ?? 0) as num).toDouble()) * dayRate;
      final tasks = data['tasks'] as List? ?? [];
      for (var t in tasks) pay += (((t['total'] ?? 0) as num).toDouble());
    }
    return pay;
  }

  double get _currentPeriodPay {
    double totalPay = 0.0;
    if (_isWeeklyView) {
      final offset = _currentDate.weekday == DateTime.sunday
          ? 0
          : _currentDate.weekday;
      final start = _currentDate.subtract(Duration(days: offset));
      final startDay = DateTime(start.year, start.month, start.day);
      for (int i = 0; i < 7; i++) {
        final key = DateFormat(
          'yyyy-MM-dd',
        ).format(startDay.add(Duration(days: i)));
        totalPay += _getPayForDayMap(_attendanceMap[key]);
      }
    } else {
      final monthPrefix = DateFormat('yyyy-MM').format(_currentDate);
      _attendanceMap.forEach((k, v) {
        if (k.startsWith(monthPrefix)) totalPay += _getPayForDayMap(v);
      });
    }
    return totalPay;
  }

  double get _allTimeEarned {
    double total = 0.0;
    _attendanceMap.forEach((k, v) {
      total += _getPayForDayMap(v);
    });
    return total;
  }

  void _editDay(DateTime date) {
    final key = DateFormat('yyyy-MM-dd').format(date);
    final defaultWageType = _localWorkerData['wage_type'] ?? 'daily';
    final isNewEntry = !_attendanceMap.containsKey(key);

    final existingData = _attendanceMap[key];
    final currentMode = _resolveMode(existingData, defaultWageType);

    final currentData = isNewEntry
        ? {
            'fraction': 1.0,
            'ot': 0.0,
            'pieces': 0.0,
            'tasks': [],
            'mode': defaultWageType,
          }
        : Map<String, dynamic>.from(existingData!);

    currentData['mode'] = currentMode;
    _showAttendanceSheet(date, key, currentData, isNewEntry);
  }

  // 🔥 MASSIVE UI UPDATE: Dual Sliders for Independent Hours 🔥
  void _showAttendanceSheet(
    DateTime date,
    String key,
    Map<String, dynamic> currentData,
    bool isNewEntry,
  ) {
    final defaultWageType = _localWorkerData['wage_type'] ?? 'daily';
    final predefinedItems = _localWorkerData['piece_items'] ?? [];

    String mode = _resolveMode(currentData, defaultWageType);

    // Initial state loading
    double getInitialNormal() {
      if (mode != 'daily') return 8.0;
      return ((currentData['fraction'] ?? 0) as num).toDouble() * 8.0;
    }

    double getInitialOt() {
      if (mode != 'daily') return 0.0;
      return ((currentData['ot'] ?? 0) as num).toDouble();
    }

    double normalHours = isNewEntry && mode == 'daily'
        ? 8.0
        : getInitialNormal();
    double otHours = isNewEntry && mode == 'daily' ? 0.0 : getInitialOt();

    double initialPieces = mode == 'piece'
        ? (((currentData['pieces'] ?? 0) as num).toDouble())
        : 0.0;
    List<dynamic> tasks = mode == 'piece'
        ? List<dynamic>.from(currentData['tasks'] ?? [])
        : [];
    final pieceCtrl = TextEditingController(
      text: initialPieces > 0 ? initialPieces.toInt().toString() : '',
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 600),
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            // Preview rate for the Total header:
            // - EXISTING record: always show the locked wage (immutable truth).
            //   Changing +/- in the profile sheet must NOT alter this display.
            // - NEW entry: preview using _draftRate (unsaved) if set, else committed rate.
            final double previewRate = isNewEntry
                ? (_draftRate ??
                      ((_localWorkerData['rate'] ?? 0.0) as num).toDouble())
                : ((currentData['locked_daily_wage'] as num?)?.toDouble() ??
                      0.0);

            // Dynamic Day Total Calculation
            double dayTotal = mode == 'daily'
                ? (normalHours * (previewRate / 8.0)) +
                      (otHours * (previewRate / 6.0))
                : (initialPieces * previewRate) +
                      tasks.fold(
                        0.0,
                        (sum, t) =>
                            sum + (((t['total'] ?? 0) as num).toDouble()),
                      );

            return Container(
              height: MediaQuery.of(context).size.height * 0.85,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(20),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              DateFormat('EEEE, d MMMM yyyy').format(date),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.grey,
                              ),
                            ),
                            Text(
                              'Total: ₹${dayTotal.round()}', // 🔥 Use .round()
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                color: _primaryColor,
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () => setSheetState(() {
                              mode = 'daily';
                              normalHours = 8.0;
                              otHours = 0.0;
                            }),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: mode == 'daily'
                                    ? _primaryColor
                                    : Colors.grey[200],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Center(
                                child: Text(
                                  'Daily Wage',
                                  style: TextStyle(
                                    color: mode == 'daily'
                                        ? Colors.white
                                        : Colors.black87,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: InkWell(
                            onTap: () => setSheetState(() => mode = 'piece'),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: mode == 'piece'
                                    ? _primaryColor
                                    : Colors.grey[200],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Center(
                                child: Text(
                                  'Piece Rate',
                                  style: TextStyle(
                                    color: mode == 'piece'
                                        ? Colors.white
                                        : Colors.black87,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: mode == 'daily'
                        ? ListView(
                            padding: const EdgeInsets.all(20),
                            children: [
                              // 🔥 NEW: SLIDER 1 (NORMAL HOURS) 🔥
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Normal Shift (Rate ÷ 8)',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                  Text(
                                    '${normalHours.toStringAsFixed(1)} h',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Slider(
                                value: normalHours,
                                min: 0,
                                max: 8,
                                divisions: 16, // 0.5 hour increments
                                activeColor: _primaryColor,
                                onChanged: (val) {
                                  if (val == 8.0 && normalHours != 8.0)
                                    HapticFeedback.heavyImpact();
                                  setSheetState(() => normalHours = val);
                                },
                              ),
                              const Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '0h (Absent)',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  Text(
                                    '8h (Full)',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 30),

                              // 🔥 NEW: SLIDER 2 (OVERTIME HOURS) 🔥
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Overtime (Rate ÷ 6)',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.orange[800],
                                    ),
                                  ),
                                  Text(
                                    '${otHours.toStringAsFixed(1)} h',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Slider(
                                value: otHours,
                                min: 0,
                                max: 12, // Let them log up to 12 hours of OT
                                divisions: 24, // 0.5 hour increments
                                activeColor: Colors.orange,
                                onChanged: (val) {
                                  if (val == 0.0 && otHours != 0.0)
                                    HapticFeedback.heavyImpact();
                                  setSheetState(() => otHours = val);
                                },
                              ),
                              const Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '0h',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  Text(
                                    '12h Max',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          )
                        : _buildPieceContent(
                            initialPieces,
                            tasks,
                            predefinedItems,
                            pieceCtrl,
                            setSheetState,
                            context,
                          ),
                  ),
                  // 🔥 FIX: Account for both Keyboard AND Android 3-Button Nav Bar
                  Container(
                    padding: EdgeInsets.fromLTRB(
                      20,
                      10,
                      20,
                      (MediaQuery.of(context).viewInsets.bottom > 0
                              ? MediaQuery.of(context).viewInsets.bottom
                              : MediaQuery.of(context).padding.bottom) +
                          20,
                    ),
                    child: Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: () {
                              // Resolve the locked wage using the CACHE+DB system:
                              // - NEW entry: use _draftRate (unsaved) if set, otherwise
                              //   fall back to the committed DB rate. This means the admin
                              //   can adjust rate with +/- and immediately log attendance
                              //   at that new rate WITHOUT pressing Save Changes first.
                              // - EDIT: always preserve the original locked wage — immune
                              //   to any rate change, saved or unsaved, forever.
                              final double committedRate =
                                  ((_localWorkerData['rate'] ?? 0.0) as num)
                                      .toDouble();
                              final double lockedWage = isNewEntry
                                  ? (_draftRate ?? committedRate)
                                  : ((currentData['locked_daily_wage'] ?? 0.0)
                                            as num)
                                        .toDouble();

                              setState(() {
                                if (mode == 'daily') {
                                  _attendanceMap[key] = {
                                    'fraction': normalHours / 8.0,
                                    'ot': otHours,
                                    'pieces': 0.0,
                                    'tasks': [],
                                    'mode': 'daily',
                                    'locked_daily_wage': lockedWage,
                                  };
                                } else {
                                  _attendanceMap[key] = {
                                    'fraction': 0.0,
                                    'ot': 0.0,
                                    'pieces': initialPieces,
                                    'tasks': tasks,
                                    'mode': 'piece',
                                    'locked_daily_wage': lockedWage,
                                  };
                                }
                              });
                              Navigator.pop(ctx);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _primaryColor,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: const Text('CONFIRM RECORD'),
                          ),
                        ),
                        if (!isNewEntry) ...[
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: () {
                              setState(() => _attendanceMap.remove(key));
                              Navigator.pop(ctx);
                            },
                            child: const Text(
                              'Clear Record',
                              style: TextStyle(color: Colors.red),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPieceContent(
    double initialPieces,
    List<dynamic> tasks,
    List<dynamic> predefinedItems,
    TextEditingController pieceCtrl,
    StateSetter setSheetState,
    BuildContext context,
  ) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'STANDARD PIECES',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.grey,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: pieceCtrl,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText:
                'Default Pieces (Rate: ₹${_localWorkerData['rate'] ?? 0})',
            border: const OutlineInputBorder(),
          ),
          onChanged: (val) =>
              setSheetState(() => initialPieces = double.tryParse(val) ?? 0.0),
        ),
        const SizedBox(height: 25),
        const Divider(),
        const SizedBox(height: 15),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'LINKED JOB TASKS',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
                letterSpacing: 1,
              ),
            ),
            TextButton.icon(
              onPressed: () async {
                await _showAddPieceTaskDialog(context, predefinedItems, (
                  newTask,
                ) {
                  setSheetState(() => tasks.add(newTask));
                });
              },
              icon: const Icon(Icons.add_circle, size: 16),
              label: const Text('ADD SPECIFIC JOB'),
            ),
          ],
        ),
        if (tasks.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: Text(
                'No linked jobs logged.',
                style: TextStyle(color: Colors.grey[400]),
              ),
            ),
          )
        else
          ...tasks.asMap().entries.map((e) {
            final idx = e.key;
            final t = e.value;
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              color: Colors.blue[50],
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                title: Text(
                  '${t['name']} (Page: ${t['page_no']})',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                subtitle: Text('${t['qty']} Pcs @ ₹ ${t['rate']}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '₹${t['total']}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.green[800],
                        fontSize: 14,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.delete,
                        color: Colors.red,
                        size: 20,
                      ),
                      onPressed: () => setSheetState(() => tasks.removeAt(idx)),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
      ],
    );
  }

  Future<void> _showAddPieceTaskDialog(
    BuildContext context,
    List<dynamic> predefinedItems,
    Function(Map<String, dynamic>) onAdd,
  ) async {
    final pageCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final qtyCtrl = TextEditingController();
    final rateCtrl = TextEditingController();

    bool isSearchingJob = false;
    String? linkedClientName;
    bool isJobFound = false;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Link Piece Work to Job'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (predefinedItems.isNotEmpty) ...[
                      const Text(
                        'Quick Select:',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Wrap(
                        spacing: 8,
                        children: predefinedItems
                            .map(
                              (item) => ActionChip(
                                backgroundColor: Colors.blue[50],
                                label: Text(
                                  '${item['name']} (₹${item['rate']})',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue,
                                  ),
                                ),
                                onPressed: () {
                                  nameCtrl.text = item['name'];
                                  rateCtrl.text = item['rate'].toString();
                                },
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 15),
                    ],
                    TextField(
                      controller: pageCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Bill No / Job ID',
                        prefixIcon: Icon(Icons.receipt_long),
                      ),
                      onChanged: (val) async {
                        if (val.trim().isEmpty) {
                          setDialogState(() {
                            linkedClientName = null;
                            isSearchingJob = false;
                            isJobFound = false;
                          });
                          return;
                        }
                        setDialogState(() => isSearchingJob = true);
                        final job = await DatabaseHelper.instance
                            .getJobByBillNo(val.trim());
                        setDialogState(() {
                          isSearchingJob = false;
                          if (job != null) {
                            isJobFound = true;
                            linkedClientName =
                                '${job['client_name']} • ${job['product_type'] ?? 'Item'}';
                          } else {
                            isJobFound = false;
                            linkedClientName = 'No matching job found';
                          }
                        });
                      },
                    ),
                    if (isSearchingJob)
                      const Padding(
                        padding: EdgeInsets.only(top: 8.0, left: 12.0),
                        child: Text(
                          "Searching...",
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      )
                    else if (linkedClientName != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0, left: 4.0),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isJobFound
                                ? Colors.green.withOpacity(0.1)
                                : Colors.orange.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isJobFound
                                  ? Colors.green.withOpacity(0.3)
                                  : Colors.orange.withOpacity(0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isJobFound
                                    ? Icons.check_circle_rounded
                                    : Icons.warning_amber_rounded,
                                color: isJobFound
                                    ? Colors.green
                                    : Colors.orange,
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  linkedClientName!,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isJobFound
                                        ? Colors.green[800]
                                        : Colors.orange[800],
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 15),
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(labelText: 'Task Name'),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: qtyCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Total Pieces',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: rateCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Rate per Piece (₹)',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (nameCtrl.text.isEmpty ||
                        qtyCtrl.text.isEmpty ||
                        rateCtrl.text.isEmpty)
                      return;
                    final q = double.tryParse(qtyCtrl.text) ?? 0;
                    final r = double.tryParse(rateCtrl.text) ?? 0;
                    onAdd({
                      'id': DateTime.now().millisecondsSinceEpoch.toString(),
                      'page_no': pageCtrl.text,
                      'name': nameCtrl.text,
                      'qty': q,
                      'rate': r,
                      'total': q * r,
                      'client_name': isJobFound ? linkedClientName : null,
                    });
                    Navigator.pop(ctx);
                  },
                  child: const Text('Add Task'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showAddPaymentDialog() async {
    final workerId = _localWorkerData['id'];

    DateTime now = DateTime.now();
    DateTime selectedDate = now;

    DateTime startOfPeriod;
    DateTime endOfPeriod;

    if (_isWeeklyView) {
      int offset = _currentDate.weekday == DateTime.sunday
          ? 0
          : _currentDate.weekday;
      startOfPeriod = _currentDate.subtract(Duration(days: offset));
      startOfPeriod = DateTime(
        startOfPeriod.year,
        startOfPeriod.month,
        startOfPeriod.day,
      );
      endOfPeriod = startOfPeriod.add(const Duration(days: 6));
    } else {
      startOfPeriod = DateTime(_currentDate.year, _currentDate.month, 1);
      int daysInMonth = DateUtils.getDaysInMonth(
        _currentDate.year,
        _currentDate.month,
      );
      endOfPeriod = DateTime(
        _currentDate.year,
        _currentDate.month,
        daysInMonth,
      );
    }

    if (now.isBefore(startOfPeriod) ||
        now.isAfter(endOfPeriod.add(const Duration(days: 1)))) {
      selectedDate = DateTime(
        endOfPeriod.year,
        endOfPeriod.month,
        endOfPeriod.day,
        12,
        0,
        0,
      );
    }

    final amtCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              elevation: 0,
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Header
                        Container(
                          width: double.infinity,
                          color: _primaryColor,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 14),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(7),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.payments_rounded,
                                  color: Colors.white,
                                  size: 19,
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text(
                                  'Add Payment',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close_rounded,
                                    color: Colors.white70, size: 20),
                                onPressed: () => Navigator.pop(ctx),
                                tooltip: "Close",
                                splashRadius: 18,
                              ),
                            ],
                          ),
                        ),

                        // Body
                        Flexible(
                          child: Container(
                            color: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 22, vertical: 20),
                            child: SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "PAYMENT DETAILS",
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blueGrey[600],
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 8),

                                  // Date selector
                                  InkWell(
                                    onTap: () async {
                                      final picked = await showDatePicker(
                                        context: context,
                                        initialDate: selectedDate,
                                        firstDate: DateTime(2020),
                                        lastDate: DateTime(2101),
                                      );
                                      if (picked != null) {
                                        setDialogState(
                                            () => selectedDate = picked);
                                      }
                                    },
                                    borderRadius: BorderRadius.circular(10),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 12),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF8FAFC),
                                        border: Border.all(
                                            color: Colors.blueGrey.shade200),
                                        borderRadius:
                                            BorderRadius.circular(10),
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.calendar_today_rounded,
                                                color: _primaryColor,
                                                size: 18,
                                              ),
                                              const SizedBox(width: 10),
                                              Text(
                                                DateFormat('dd MMM yyyy')
                                                    .format(selectedDate),
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 14,
                                                  color: Color(0xFF1E293B),
                                                ),
                                              ),
                                            ],
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: Colors.blueGrey
                                                  .withOpacity(0.08),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              "Change",
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.blueGrey[700],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 14),

                                  // Amount Paid field
                                  TextField(
                                    controller: amtCtrl,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF0F172A),
                                    ),
                                    decoration: InputDecoration(
                                      labelText: 'Amount Paid',
                                      labelStyle: TextStyle(
                                        color: Colors.blueGrey[600],
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      prefixIcon: Container(
                                        width: 44,
                                        alignment: Alignment.center,
                                        child: Text(
                                          '₹',
                                          style: TextStyle(
                                            fontSize: 22,
                                            fontWeight: FontWeight.bold,
                                            color: _primaryColor,
                                          ),
                                        ),
                                      ),
                                      filled: true,
                                      fillColor: const Color(0xFFF8FAFC),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 16, vertical: 14),
                                      border: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(10),
                                        borderSide: BorderSide(
                                            color: Colors.blueGrey.shade200),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(10),
                                        borderSide: BorderSide(
                                            color: Colors.blueGrey.shade200),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(10),
                                        borderSide: BorderSide(
                                            color: _primaryColor, width: 2),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        // Footer
                        Container(
                          width: double.infinity,
                          color: const Color(0xFFF8FAFC),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              OutlinedButton(
                                onPressed: () => Navigator.pop(ctx),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.blueGrey[700],
                                  side: BorderSide(
                                      color: Colors.blueGrey.shade300),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 11),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8)),
                                ),
                                child: const Text("Cancel",
                                    style:
                                        TextStyle(fontWeight: FontWeight.w600)),
                              ),
                              const SizedBox(width: 10),
                              ElevatedButton.icon(
                                onPressed: () async {
                                  double amount =
                                      double.tryParse(amtCtrl.text) ?? 0.0;
                                  if (amount > 0) {
                                    int offset =
                                        selectedDate.weekday == DateTime.sunday
                                            ? 0
                                            : selectedDate.weekday;
                                    DateTime correctWeekStart =
                                        selectedDate.subtract(
                                      Duration(days: offset),
                                    );
                                    String weekKey = DateFormat('yyyy-MM-dd')
                                        .format(correctWeekStart);

                                    await DatabaseHelper.instance
                                        .markWeeklyPayment(
                                      workerId,
                                      weekKey,
                                      amount,
                                      paidDate: selectedDate.toIso8601String(),
                                    );
                                  }
                                  if (context.mounted) Navigator.pop(ctx);
                                  _loadPayment();
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _primaryColor,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 20, vertical: 11),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8)),
                                  elevation: 1,
                                ),
                                icon: const Icon(Icons.check_rounded, size: 18),
                                label: const Text("Add Payment",
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openPayslipPreview() async {
    final currentEarned = _currentPeriodPay.roundToDouble();
    final currentPaid = _currentPaymentHistory
        .fold(0.0, (s, e) => s + (e['amount'] as num).toDouble())
        .roundToDouble();

    int daysWorked = 0;
    int absentDays = 0;

    double totalNormalHours = 0;
    double totalOtHours = 0;
    double totalPieces = 0;
    int totalTasks = 0;

    List<Map<String, String>> dailyRecords = [];
    final defaultWageType = _localWorkerData['wage_type'] ?? 'daily';
    final baseRate = _localWorkerData['rate'] ?? 0.0;

    DateTime startDay;
    int loopDays;

    if (_isWeeklyView) {
      final offset = _currentDate.weekday == DateTime.sunday
          ? 0
          : _currentDate.weekday;
      startDay = _currentDate.subtract(Duration(days: offset));
      loopDays = 7;
    } else {
      startDay = DateTime(_currentDate.year, _currentDate.month, 1);
      loopDays = DateUtils.getDaysInMonth(
        _currentDate.year,
        _currentDate.month,
      );
    }

    final todayNormalized = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );

    for (int i = 0; i < loopDays; i++) {
      final currentDay = startDay.add(Duration(days: i));
      final currentDayNormalized = DateTime(
        currentDay.year,
        currentDay.month,
        currentDay.day,
      );

      final bool isFuture = currentDayNormalized.isAfter(todayNormalized);
      final key = DateFormat('yyyy-MM-dd').format(currentDay);
      final displayDate = DateFormat('dd MMM').format(currentDay);

      if (_attendanceMap.containsKey(key)) {
        final d = _attendanceMap[key];
        final mode = _resolveMode(d, defaultWageType);
        bool isAbsent = false;

        if (mode == 'daily') {
          final nH = ((d['fraction'] ?? 0) as num).toDouble() * 8.0;
          final oH = ((d['ot'] ?? 0) as num).toDouble();

          totalNormalHours += nH;
          totalOtHours += oH;

          if (nH == 0 && oH == 0) {
            isAbsent = true;
          } else {
            daysWorked++;
            if (nH > 0) {
              dailyRecords.add({
                'date': displayDate,
                'work': 'Regular Shift',
                'qty_rate': '${nH.toStringAsFixed(1)} Hrs',
                'earned': (nH * (baseRate / 8.0)).round().toString(),
              });
            }
            if (oH > 0) {
              dailyRecords.add({
                'date': displayDate,
                'work': 'Overtime',
                'qty_rate': '${oH.toStringAsFixed(1)} Hrs',
                'earned': (oH * (baseRate / 6.0)).round().toString(),
              });
            }
          }
        } else {
          final p = ((d['pieces'] ?? 0) as num).toDouble();
          final tList = d['tasks'] as List? ?? [];

          totalPieces += p;
          totalTasks += tList.length;

          if (p == 0 &&
              tList.isEmpty &&
              ((d['fraction'] ?? 0) as num).toDouble() == 0) {
            isAbsent = true;
          } else {
            daysWorked++;

            if (p > 0) {
              dailyRecords.add({
                'date': displayDate,
                'work': 'Standard Pieces',
                'qty_rate': '${p.toInt()} pcs @ Rs. ${baseRate.round()}',
                'earned': (p * baseRate).round().toString(),
              });
            }

            for (var t in tList) {
              String tName = t['name']?.toString() ?? 'Specific Task';
              String pageStr = t['page_no']?.toString() ?? '';
              if (pageStr.isNotEmpty) {
                tName += " (Bill: $pageStr)";
              }

              double tQty = (t['qty'] as num?)?.toDouble() ?? 0.0;
              double tRate = (t['rate'] as num?)?.toDouble() ?? 0.0;
              double tTotal = (t['total'] as num?)?.toDouble() ?? 0.0;

              dailyRecords.add({
                'date': displayDate,
                'work': tName,
                'qty_rate': '${tQty.toInt()} pcs @ Rs. ${tRate.round()}',
                'earned': tTotal.round().toString(),
              });
            }
          }
        }

        if (isAbsent && !isFuture) {
          absentDays++;
        }
      } else {
        if (!isFuture) {
          absentDays++;
        }
      }
    }

    try {
      final sanitizedName = (_localWorkerData['name'] ?? 'Worker')
          .toString()
          .replaceAll(RegExp(r'[^\w\s]+'), '')
          .trim();
      final docName = 'PaySlip_${sanitizedName}_$_periodLabel'.replaceAll(
        RegExp(r'[^\w\s-]+'),
        '',
      );

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) {
          final screenSize = MediaQuery.of(ctx).size;
          final dialogWidth = (screenSize.width * 0.9).clamp(320.0, 950.0);
          final dialogHeight = (screenSize.height * 0.9).clamp(400.0, 850.0);

          return Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            shadowColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 20,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: SizedBox(
                width: dialogWidth,
                height: dialogHeight,
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      color: const Color(0xFF1E293B),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.picture_as_pdf_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'Payslip Preview (${_localWorkerData['name']} - $_periodLabel)',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.close_rounded,
                              color: Colors.white,
                              size: 22,
                            ),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Container(
                        color: Colors.white,
                        child: PdfPreview(
                          build: (format) async =>
                              await WagePdfService.generatePayslip(
                                workerName:
                                    _localWorkerData['name'] ?? 'Worker',
                                periodLabel: _periodLabel,
                                totalEarned: currentEarned,
                                totalPaid: currentPaid,
                                daysWorked: daysWorked,
                                absentDays: absentDays,
                                normalHours: totalNormalHours,
                                otHours: totalOtHours,
                                pieces: totalPieces,
                                tasks: totalTasks,
                                dailyRecords: dailyRecords,
                              ),
                          pdfFileName: '$docName.pdf',
                          allowPrinting: true,
                          allowSharing: true,
                          canChangePageFormat: false,
                          canChangeOrientation: false,
                          canDebug: false,
                          loadingWidget: const Center(
                            child: CircularProgressIndicator(),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error generating PDF: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    double overallBalance = _allTimeEarned - _allTimePaid;
    String overStatus = overallBalance < 0
        ? "Advance: ₹${overallBalance.abs().round()}" // 🔥 Use .round()
        : (overallBalance > 0
              ? "Pending Due: ₹${overallBalance.round()}" // 🔥 Use .round()
              : "All Clear");
    Color overColor = overallBalance < 0
        ? Colors.orange[800]!
        : (overallBalance > 0 ? Colors.red[700]! : Colors.green[700]!);
    Color overBg = overallBalance < 0
        ? Colors.orange[50]!
        : (overallBalance > 0 ? Colors.red[50]! : Colors.green[50]!);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(
            widget.isDialog ? Icons.close_rounded : Icons.arrow_back_rounded,
          ),
          tooltip: widget.isDialog ? 'Close' : 'Back',
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(_localWorkerData['name'] ?? 'Worker'),
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
        actions: [
          GestureDetector(
            onTap: _showEditProfileSheet,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Center(
                child: Text(
                  'EDIT',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.receipt_long),
            tooltip: 'Preview / Share Payslip',
            onPressed: _openPayslipPreview,
          ),
          PopupMenuButton<bool>(
            icon: const Icon(Icons.more_vert),
            onSelected: (bool isWeekly) {
              setState(() => _isWeeklyView = isWeekly);
              _loadPayment();
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<bool>>[
              CheckedPopupMenuItem<bool>(
                value: true,
                checked: _isWeeklyView,
                child: const Text('Weekly View'),
              ),
              CheckedPopupMenuItem<bool>(
                value: false,
                checked: !_isWeeklyView,
                child: const Text('Monthly View'),
              ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: SafeArea(
          child: Row(
            children: [
              if (widget.isDialog) ...[
                OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                    side: BorderSide(color: Colors.grey[300]!),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'Discard',
                    style: TextStyle(
                      color: Colors.black87,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _saveAndPop,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'SAVE CHANGES',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildWorkerIdentityBar(),
                const SizedBox(height: 10),
                _buildStatsRow(overBg, overColor, overStatus),
                const SizedBox(height: 10),
                _buildPeriodNavRow(),
                const SizedBox(height: 8),
                _buildCalendar(),
                const SizedBox(height: 8),
                _buildPaymentSummary(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWorkerIdentityBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _primaryColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                (_localWorkerData['name'] as String? ?? 'W')
                    .trim()
                    .split(' ')
                    .map((p) => p.isNotEmpty ? p[0] : '')
                    .take(2)
                    .join()
                    .toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    _localWorkerData['name'] ?? '',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Builder(
                  builder: (_) {
                    final st =
                        (_localWorkerData['status'] ?? 'Active') as String;
                    final Color badgeBg = st == 'Active'
                        ? Colors.green[400]!
                        : st == 'Vacation'
                        ? Colors.blue[300]!
                        : Colors.grey[500]!;
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: badgeBg,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        st.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Rate: \u20b9${(_localWorkerData['rate'] ?? 0).toStringAsFixed(0)} / ${_localWorkerData['wage_type'] == 'piece' ? 'pc' : 'day'}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 10),
          if ((_localWorkerData['employee_phone'] ?? '').isNotEmpty)
            GestureDetector(
              onTap: () =>
                  _launchPhone(_localWorkerData['employee_phone'] as String),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.green[500],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.phone_rounded,
                      color: Colors.white,
                      size: 13,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      _localWorkerData['employee_phone'],
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            GestureDetector(
              onTap: _showEditProfileSheet,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Add Phone',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatsRow(Color overBg, Color overColor, String overStatus) {
    final paidAmt = _currentPaymentHistory.fold(
      0.0,
      (s, e) => s + (e['amount'] as num).toDouble(),
    );
    final diff = paidAmt - _currentPeriodPay;
    String periodPayStatus = "No Dues";
    Color periodPayColor = Colors.white70;
    if (diff > 0) {
      periodPayStatus = "+ \u20b9${diff.round()} Advance";
      periodPayColor = Colors.orange[300]!;
    } else if (diff < 0) {
      periodPayStatus = "- \u20b9${diff.abs().round()} Due";
      periodPayColor = Colors.amber[300]!;
    } else if (_currentPeriodPay > 0 && diff == 0) {
      periodPayStatus = "Fully Paid";
      periodPayColor = Colors.green[300]!;
    }

    return Row(
      children: [
        // Overall Balance
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: overBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: overColor.withValues(alpha: 0.25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "OVERALL ACCOUNT BALANCE",
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[700],
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  overStatus,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: overColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  "Earned: \u20b9${_allTimeEarned.round()}  \u2022  Paid: \u20b9${_allTimePaid.round()}",
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Current Period Earnings
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isWeeklyView ? 'Earned This Week' : 'Earned This Month',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '\u20b9${_currentPeriodPay.round()}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      periodPayStatus,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: periodPayColor,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.account_balance_wallet_rounded,
                    color: Colors.white70,
                    size: 24,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPeriodNavRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left_rounded, size: 22),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              onPressed: () => _changePeriod(-1),
            ),
            Text(
              _periodLabel,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right_rounded, size: 22),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              onPressed: () => _changePeriod(1),
            ),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.all(2),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      if (!_isWeeklyView) {
                        setState(() => _isWeeklyView = true);
                        _loadPayment();
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _isWeeklyView
                            ? Colors.white
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        boxShadow: _isWeeklyView
                            ? [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.06),
                                  blurRadius: 4,
                                ),
                              ]
                            : null,
                      ),
                      child: Text(
                        'Week',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: _isWeeklyView
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: _isWeeklyView
                              ? _primaryColor
                              : Colors.grey[700],
                        ),
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      if (_isWeeklyView) {
                        setState(() => _isWeeklyView = false);
                        _loadPayment();
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: !_isWeeklyView
                            ? Colors.white
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        boxShadow: !_isWeeklyView
                            ? [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.06),
                                  blurRadius: 4,
                                ),
                              ]
                            : null,
                      ),
                      child: Text(
                        'Month',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: !_isWeeklyView
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: !_isWeeklyView
                              ? _primaryColor
                              : Colors.grey[700],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _openPayslipPreview,
              icon: const Icon(Icons.receipt_long_rounded, size: 15),
              label: const Text(
                'Payslip',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                side: BorderSide(color: _primaryColor.withOpacity(0.3)),
                foregroundColor: _primaryColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDayHeaders() {
    const days = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: Row(
        children: List.generate(
          7,
          (index) => Expanded(
            child: Center(
              child: Text(
                days[index],
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: index == 0 ? Colors.red[400] : Colors.grey[600],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCalendar() {
    Widget grid;
    if (_isWeeklyView) {
      final offset = _currentDate.weekday == DateTime.sunday
          ? 0
          : _currentDate.weekday;
      final start = _currentDate.subtract(Duration(days: offset));
      final startDay = DateTime(start.year, start.month, start.day);
      grid = GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 7,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.85,
        ),
        itemCount: 7,
        itemBuilder: (context, index) =>
            _buildDayCell(startDay.add(Duration(days: index))),
      );
    } else {
      final daysInMonth = DateUtils.getDaysInMonth(
        _currentDate.year,
        _currentDate.month,
      );
      final firstDayOfMonth = DateTime(
        _currentDate.year,
        _currentDate.month,
        1,
      );
      final firstDayOffset = firstDayOfMonth.weekday == DateTime.sunday
          ? 0
          : firstDayOfMonth.weekday;
      grid = GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 7,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          childAspectRatio: 1.45,
        ),
        itemCount: daysInMonth + firstDayOffset,
        itemBuilder: (context, index) {
          if (index < firstDayOffset) return const SizedBox();
          return _buildDayCell(
            DateTime(
              _currentDate.year,
              _currentDate.month,
              index - firstDayOffset + 1,
            ),
          );
        },
      );
    }
    return Column(children: [_buildDayHeaders(), grid]);
  }

  Widget _buildDayCell(DateTime date) {
    final key = DateFormat('yyyy-MM-dd').format(date);
    final data = _attendanceMap[key];
    final defaultWageType = _localWorkerData['wage_type'] ?? 'daily';
    final mode = _resolveMode(data, defaultWageType);

    bool isExplicitlyAbsent = false;
    double hours = 0.0;
    double normalHours = 0.0;
    double otHours = 0.0;
    double pieces = 0.0;
    List tasks = [];

    if (data != null) {
      if (mode == 'daily') {
        normalHours = ((data['fraction'] ?? 0) as num).toDouble() * 8.0;
        otHours = ((data['ot'] ?? 0) as num).toDouble();
        hours = normalHours + otHours;
        isExplicitlyAbsent = hours == 0.0;
      } else if (mode == 'piece') {
        pieces = (((data['pieces'] ?? 0) as num).toDouble());
        tasks = data['tasks'] as List? ?? [];
        isExplicitlyAbsent =
            tasks.isEmpty &&
            pieces == 0.0 &&
            (((data['fraction'] ?? 0) as num).toDouble() == 0.0);
      }
    }

    Color bg = date.weekday == DateTime.sunday
        ? Colors.red[50]!
        : Colors.grey[100]!;
    Color text = date.weekday == DateTime.sunday ? Colors.red : Colors.black;
    Border? border;

    if (isExplicitlyAbsent && data != null) {
      bg = Colors.red[100]!;
      text = Colors.red[900]!;
    } else if (mode == 'piece' && (pieces > 0 || tasks.isNotEmpty)) {
      bg = Colors.indigo[100]!;
      text = Colors.indigo[900]!;
    } else if (mode == 'daily' && hours > 0) {
      if (hours < 8) {
        bg = Colors.orange[100]!;
        text = Colors.brown;
      } else if (hours == 8 && otHours == 0) {
        bg = Colors.green[100]!;
        text = Colors.green[900]!;
      } else {
        bg = const Color(0xFFD1C4E9);
        text = Colors.deepPurple;
        border = Border.all(color: Colors.deepPurple, width: 2);
      }
    }

    return InkWell(
      onTap: () => _editDay(date),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          border: border,
        ),
        child: Stack(
          children: [
            Center(
              child: Text(
                '${date.day}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: text,
                  fontSize: 14,
                ),
              ),
            ),
            if (isExplicitlyAbsent && data != null)
              Positioned(
                bottom: 3,
                right: 5,
                child: Text(
                  'Absent',
                  style: TextStyle(
                    fontSize: 8,
                    color: text,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            else if (mode == 'piece' && (pieces > 0 || tasks.isNotEmpty))
              Positioned(
                bottom: 3,
                right: 5,
                child: Text(
                  '${pieces > 0 ? '${pieces.toInt()}p ' : ''}${tasks.isNotEmpty ? '+${tasks.length}T' : ''}'
                      .trim(),
                  style: TextStyle(
                    fontSize: 8,
                    color: text,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            else if (mode == 'daily' && hours > 0)
              if (!(normalHours == 8 && otHours == 0))
                Positioned(
                  bottom: 3,
                  right: 5,
                  child: Text(
                    otHours > 0
                        ? '${normalHours.toStringAsFixed(normalHours.truncateToDouble() == normalHours ? 0 : 1)}h+${otHours.toStringAsFixed(otHours.truncateToDouble() == otHours ? 0 : 1)}ot'
                        : '${normalHours.toStringAsFixed(normalHours.truncateToDouble() == normalHours ? 0 : 1)}h',
                    style: TextStyle(
                      fontSize: 8,
                      color: text,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentSummary() {
    final earned = _currentPeriodPay;
    final paidAmt = _currentPaymentHistory.fold(
      0.0,
      (s, e) => s + (e['amount'] as num).toDouble(),
    );
    final diff = paidAmt - earned;

    String statusText;
    Color statusColor;

    if (diff > 0) {
      statusText = "+ \u20b9${diff.round()} (Advance)";
      statusColor = Colors.orange[800]!;
    } else if (diff < 0) {
      statusText = "- \u20b9${diff.abs().round()} (Pending)";
      statusColor = Colors.red[700]!;
    } else if (earned > 0 && diff == 0) {
      statusText = "Fully Paid";
      statusColor = Colors.green[700]!;
    } else {
      statusText = "No Dues";
      statusColor = Colors.grey[700]!;
    }

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    _isWeeklyView ? "WEEKLY LEDGER" : "MONTHLY LEDGER",
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[700],
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      statusText,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: _showAddPaymentDialog,
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _primaryColor,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.add, size: 13, color: Colors.white),
                      SizedBox(width: 3),
                      Text(
                        "RECORD PAYMENT",
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (_currentPaymentHistory.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: _currentPaymentHistory.map((p) {
                DateTime pDate =
                    DateTime.tryParse(p['paid_date'] ?? '') ?? DateTime.now();
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.green[200]!),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "${DateFormat('dd MMM').format(pDate)}: ",
                        style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                      ),
                      Text(
                        "\u20b9${p['amount']}",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.green[800],
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(width: 4),
                      InkWell(
                        onTap: () async {
                          await DatabaseHelper.instance.deleteSinglePayment(
                            p['id'],
                          );
                          _loadPayment();
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: const Icon(
                          Icons.close_rounded,
                          size: 13,
                          color: Colors.red,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}
