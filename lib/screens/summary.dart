import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart'; // REQUIRED FOR POPUP
import '../database_helper.dart';

class SummaryView extends StatefulWidget {
  const SummaryView({super.key});

  @override
  State<SummaryView> createState() => _SummaryViewState();
}

class _SummaryViewState extends State<SummaryView> {
  bool _isLoading = true;

  // Default to current month
  DateTime _startDate = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _endDate = DateTime(
    DateTime.now().year,
    DateTime.now().month + 1,
    0,
    23,
    59,
    59,
  );

  // --- Aggregated Financial Data ---
  double _grossBilled = 0.0; // Original Total Cost without deductions
  double _totalDiscount = 0.0; // Total Discounts Given
  double _totalScrap = 0.0; // Total Scrap Adjustments
  double _netBilled = 0.0; // Gross - Discount - Scrap

  double _totalIncome = 0.0; // Actual cash received (Ledger)
  double _totalAdvancesOnJobs = 0.0; // Advances logged directly on job creation
  double _totalWages = 0.0; // Cash given to workers (wages + advance)

  // --- Detailed Data Lists ---
  List<Map<String, dynamic>> _clientPaymentsList = [];
  List<Map<String, dynamic>> _workerPaymentsList = [];
  List<Map<String, dynamic>> _clientDues = [];
  List<Map<String, dynamic>> _leftoverMaterials = [];

  // 🔥 EXPLICIT DEDUCTION LISTS
  List<Map<String, dynamic>> _discountsList = [];
  List<Map<String, dynamic>> _scrapList = [];

  Map<String, int> _materialsIn = {};
  Map<String, int> _productsOut = {};

  final Color _primaryColor = const Color(0xFF1A237E);

  @override
  void initState() {
    super.initState();
    _fetchSummaryData();

    // 🔥 Check if we should show the notice
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndShowUpgradeNotice();
    });
  }

  // 🔥 CHECK PREFERENCES FOR POPUP 🔥
  Future<void> _checkAndShowUpgradeNotice() async {
    final prefs = await SharedPreferences.getInstance();
  }

  // 🔥 UPGRADED PROFESSIONAL NOTICE DIALOG UI/UX 🔥

  // Helper for the popup bullet points
  Widget _buildUpdatePoint({
    required IconData icon,
    required String title,
    required String desc,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: _primaryColor, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                desc,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _selectDateRange(BuildContext context) async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
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

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = DateTime(
          picked.end.year,
          picked.end.month,
          picked.end.day,
          23,
          59,
          59,
        );
      });
      _fetchSummaryData();
    }
  }

  Future<void> _fetchSummaryData() async {
    setState(() => _isLoading = true);
    try {
      final db = await DatabaseHelper.instance.database;
      String sDate = _startDate.toIso8601String();
      String eDate = _endDate.toIso8601String();

      // 1. FINANCIAL TRANSACTIONS (REVENUE, SCRAP, DISCOUNT)
      var revRes = await db.rawQuery(
        '''
        SELECT p.id as payment_id, p.amount, p.payment_date AS transaction_date, p.notes, j.client_name, j.bill_no, j.created_at AS bill_date 
        FROM payments p 
        JOIN jobs j ON p.job_id = j.id 
        WHERE p.payment_date >= ? AND p.payment_date <= ?
        ORDER BY p.payment_date DESC
      ''',
        [sDate, eDate],
      );

      _totalIncome = 0.0;
      _totalDiscount = 0.0;
      _totalScrap = 0.0;
      _clientPaymentsList = [];
      _discountsList.clear();
      _scrapList.clear();

      for (var row in revRes) {
        var p = Map<String, dynamic>.from(row);
        String note = (p['notes'] ?? '').toString().toLowerCase();

        if (note.contains('discount') || note.contains('disc')) {
          double amt = (p['amount'] as num?)?.toDouble() ?? 0.0;
          if (amt == 0.0) {
            final match = RegExp(r'[\d\.]+').firstMatch(note);
            if (match != null) amt = double.tryParse(match.group(0)!) ?? 0.0;
          }
          _totalDiscount += amt;
          _discountsList.add({
            'payment_id': p['payment_id'],
            'client_name': p['client_name'] ?? 'Unknown',
            'bill_no': p['bill_no']?.toString() ?? '',
            'amount': amt,
            'transaction_date': p['transaction_date'],
            'bill_date': p['bill_date'],
          });
        } else if (note.contains('scrap')) {
          double amt = (p['amount'] as num?)?.toDouble() ?? 0.0;
          if (amt == 0.0) {
            final match = RegExp(r'[\d\.]+').firstMatch(note);
            if (match != null) amt = double.tryParse(match.group(0)!) ?? 0.0;
          }
          _totalScrap += amt;
          _scrapList.add({
            'payment_id': p['payment_id'],
            'client_name': p['client_name'] ?? 'Unknown',
            'bill_no': p['bill_no']?.toString() ?? '',
            'amount': amt,
            'transaction_date': p['transaction_date'],
            'bill_date': p['bill_date'],
          });
        } else {
          _totalIncome += (p['amount'] as num?)?.toDouble() ?? 0.0;
          p['payment_date'] = p['transaction_date'];
          _clientPaymentsList.add(p);
        }
      }

      // 2. EXPENSES / CASH OUTFLOW
      var wageRes = await db.rawQuery(
        '''
        SELECT wph.amount, wph.paid_date, w.name as worker_name 
        FROM worker_payment_history wph 
        JOIN workers w ON wph.worker_id = w.id 
        WHERE wph.paid_date >= ? AND wph.paid_date <= ?
        ORDER BY wph.paid_date DESC
      ''',
        [sDate, eDate],
      );

      _totalWages = 0.0;
      _workerPaymentsList = List<Map<String, dynamic>>.from(wageRes);
      for (var w in _workerPaymentsList) {
        _totalWages += (w['amount'] as num?)?.toDouble() ?? 0.0;
      }

      // 3. FETCH JOBS CREATED IN THIS PERIOD
      var jobs = await db.rawQuery(
        "SELECT * FROM jobs WHERE created_at >= ? AND created_at <= ? ORDER BY created_at DESC",
        [sDate, eDate],
      );

      _grossBilled = 0.0;
      _netBilled = 0.0;
      _totalAdvancesOnJobs = 0.0;

      _clientDues.clear();
      _leftoverMaterials.clear();
      Map<String, int> tempMatIn = {};

      for (var job in jobs) {
        int jobId = job['id'] as int;
        double grossCost = (job['total_cost'] as num?)?.toDouble() ?? 0.0;

        // 🔥 EXTRACTING SCRAP AND DISCOUNT SECURELY 🔥
        double discount = 0.0;
        double scrapValue = 0.0;
        double advancePaid = 0.0;

        if (job.containsKey('discount') && job['discount'] != null) {
          discount = (job['discount'] as num).toDouble();
        }
        if (job.containsKey('scrap_value') && job['scrap_value'] != null) {
          scrapValue = (job['scrap_value'] as num).toDouble();
        }
        if (job.containsKey('advance_paid') && job['advance_paid'] != null) {
          advancePaid = (job['advance_paid'] as num).toDouble();
        }

        List<dynamic> inList = [];
        List<dynamic> outList = [];

        try {
          final data = jsonDecode(job['items'].toString());
          inList = data['in'] ?? [];
          outList = data['out'] ?? [];

          if (discount == 0.0)
            discount = (data['discount'] as num?)?.toDouble() ?? 0.0;
          if (scrapValue == 0.0)
            scrapValue = (data['scrap_value'] as num?)?.toDouble() ?? 0.0;
          if (advancePaid == 0.0)
            advancePaid = (data['advance'] as num?)?.toDouble() ?? 0.0;
        } catch (_) {}

        // CALCULATE NET BILL
        double netJobCost = grossCost - discount - scrapValue;

        _grossBilled += grossCost;
        _totalAdvancesOnJobs += advancePaid;

        // Calculate exact due: Net Cost - (Ledger Payments + Job Advance)
        var payRes = await db.rawQuery(
          "SELECT SUM(amount) as total FROM payments WHERE job_id = ?",
          [jobId],
        );
        double paidFromLedger =
            (payRes.first['total'] as num?)?.toDouble() ?? 0.0;
        double totalPaidForJob = paidFromLedger + advancePaid;
        double due = netJobCost - totalPaidForJob;

        if (due >= 1.0) {
          _clientDues.add({
            'client_name': job['client_name'] ?? 'Unknown',
            'bill_no': job['bill_no']?.toString() ?? jobId.toString(),
            'due': due,
            'date': job['created_at'],
            'phone': job['client_phone'],
          });
        }

        // --- Materials In & Out Logic ---
        if (inList.isEmpty &&
            job['material_brought'] != null &&
            job['material_brought'].toString().isNotEmpty) {
          inList.add({
            'name': job['material_brought'],
            'qty': job['qty_given'],
            'id': 'legacy_in',
          });
        }
        if (outList.isEmpty &&
            job['product_type'] != null &&
            job['product_type'].toString().isNotEmpty) {
          outList.add({
            'name': job['product_type'],
            'qty': job['target_qty'],
            'linked_materials': [],
          });
        }

        for (var m in inList) {
          String n = m['name']?.toString() ?? 'Unknown';
          int q = (m['qty'] as num?)?.toInt() ?? 0;
          tempMatIn[n] = (tempMatIn[n] ?? 0) + q;
        }

        List<String> leftovers = [];
        for (var mat in inList) {
          String matId = mat['id']?.toString() ?? '';
          String mName = mat['name']?.toString() ?? 'Unknown';
          int totalQty = (mat['qty'] as num?)?.toInt() ?? 0;
          int usedQty = 0;

          for (var prod in outList) {
            List links = prod['linked_materials'] ?? [];
            if (links.isEmpty && prod['linked_ids'] != null) {
              links = (prod['linked_ids'] as List)
                  .map((id) => {'id': id, 'used_qty': 1})
                  .toList();
            }
            for (var link in links) {
              if (link['id'] == matId) {
                usedQty += (link['used_qty'] as num?)?.toInt() ?? 0;
              }
            }
          }

          int rem = totalQty - usedQty;
          if (rem > 0) leftovers.add("$mName: $rem remaining");
        }

        if (leftovers.isNotEmpty) {
          _leftoverMaterials.add({
            'client_name': job['client_name'] ?? 'Unknown',
            'bill_no': job['bill_no']?.toString() ?? jobId.toString(),
            'date': job['created_at'],
            'status': job['status'] ?? 'Ongoing',
            'leftovers': leftovers,
          });
        }
      }
      _materialsIn = tempMatIn;

      _netBilled = _grossBilled - _totalDiscount - _totalScrap;

      // 4. PRODUCTS OUT
      var delRes = await db.rawQuery(
        "SELECT item_name, SUM(qty_delivered) as total FROM deliveries WHERE delivery_date >= ? AND delivery_date <= ? GROUP BY item_name",
        [sDate, eDate],
      );
      Map<String, int> tempProdOut = {};
      for (var row in delRes) {
        tempProdOut[row['item_name'].toString()] = (row['total'] as num)
            .toInt();
      }
      _productsOut = tempProdOut;
    } catch (e) {
      debugPrint("Summary Error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final formatCurrency = NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 0,
    );

    double totalCashInHand = _totalIncome + _totalAdvancesOnJobs;
    double netCashFlow = totalCashInHand - _totalWages;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text(
          "Business Summary",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [],
      ),
      body: Column(
        children: [
          // --- DATE RANGE HEADER ---
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
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
                const Text(
                  "CURRENT SELECTED PERIOD",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () => _selectDateRange(context),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.calendar_month_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          "${DateFormat('dd MMM yyyy').format(_startDate)}  -  ${DateFormat('dd MMM yyyy').format(_endDate)}",
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Icon(Icons.edit, color: Colors.white70, size: 14),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // --- MAIN CONTENT AREA ---
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 🔥 1. BILLING & REVENUE CARD 🔥
                        _buildSectionTitle("1. BILLING & REVENUE"),
                        Card(
                          elevation: 2,
                          color: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              children: [
                                _buildFinanceRow(
                                  "(+) Gross Estimates",
                                  formatCurrency.format(_grossBilled),
                                  Colors.blueGrey[800]!,
                                  subtitle: "Total original bill prices",
                                ),
                                const SizedBox(height: 6),
                                _buildFinanceRow(
                                  "(-) Discounts Given",
                                  "- ${formatCurrency.format(_totalDiscount)}",
                                  Colors.orange[800]!,
                                  subtitle: "Total discounts allowed",
                                ),
                                const SizedBox(height: 6),
                                _buildFinanceRow(
                                  "(-) Scrap Deductions",
                                  "- ${formatCurrency.format(_totalScrap)}",
                                  Colors.brown[600]!,
                                  subtitle: "Value of old scrap returned",
                                ),
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 12),
                                  child: Divider(height: 1, thickness: 1),
                                ),
                                _buildFinanceRow(
                                  "(=) Net Expected Revenue",
                                  formatCurrency.format(_netBilled),
                                  Colors.black87,
                                  isTotal: true,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // 🔥 2. ACTUAL CASH FLOW CARD 🔥
                        _buildSectionTitle("2. ACTUAL CASH FLOW (IN HAND)"),
                        Card(
                          elevation: 2,
                          color: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              children: [
                                _buildFinanceRow(
                                  "(+) Total Cash Collected",
                                  formatCurrency.format(totalCashInHand),
                                  Colors.green[700]!,
                                  subtitle: "Payments + Advances received",
                                ),
                                const SizedBox(height: 6),
                                _buildFinanceRow(
                                  "(-) Worker Payouts",
                                  "- ${formatCurrency.format(_totalWages)}",
                                  Colors.red[700]!,
                                  subtitle: "Wages & Advances given out",
                                ),
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 12),
                                  child: Divider(height: 1, thickness: 1),
                                ),
                                _buildFinanceRow(
                                  "(=) Net Cash Flow",
                                  formatCurrency.format(netCashFlow),
                                  netCashFlow >= 0 ? _primaryColor : Colors.red,
                                  isTotal: true,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 25),

                        // 🔥 COLLAPSIBLE LISTS FOR CLEAN UI 🔥
                        _buildCollapsibleSection(
                          title: "PENDING DUES / UNSETTLED",
                          subtitle: "Calculated after discounts & scrap",
                          icon: Icons.account_balance_wallet_rounded,
                          color: Colors.red[600]!,
                          count: _clientDues.length,
                          children: _buildClientDuesList(),
                        ),

                        // 🔥 EXPLICIT DISCOUNT & SCRAP COLLAPSIBLE LISTS 🔥
                        _buildCollapsibleSection(
                          title: "DISCOUNTS GIVEN",
                          subtitle: "Tap to see who received discounts",
                          icon: Icons.loyalty_rounded,
                          color: Colors.orange[800]!,
                          count: _discountsList.length,
                          totalAmount: _totalDiscount,
                          children: _buildAdjustmentList(
                            _discountsList,
                            Colors.orange[800]!,
                            "Discount Given",
                          ),
                        ),

                        _buildCollapsibleSection(
                          title: "SCRAP VALUE DEDUCTIONS",
                          subtitle: "Tap to see who provided scrap",
                          icon: Icons.recycling_rounded,
                          color: Colors.brown[600]!,
                          count: _scrapList.length,
                          totalAmount: _totalScrap,
                          children: _buildAdjustmentList(
                            _scrapList,
                            Colors.brown[600]!,
                            "Scrap Deducted",
                          ),
                        ),

                        _buildCollapsibleSection(
                          title: "CASH INFLOW (CLIENT PAYMENTS)",
                          icon: Icons.arrow_downward_rounded,
                          color: Colors.green,
                          count: _clientPaymentsList.length,
                          totalAmount: _totalIncome,
                          children: _buildDetailedClientPaymentsList(),
                        ),

                        _buildCollapsibleSection(
                          title: "CASH OUTFLOW (WORKER PAYOUTS)",
                          icon: Icons.arrow_upward_rounded,
                          color: Colors.red,
                          count: _workerPaymentsList.length,
                          totalAmount: _totalWages,
                          children: _buildDetailedWorkerPaymentsList(),
                        ),

                        _buildCollapsibleSection(
                          title: "REMAINING RAW MATERIALS (LEFTOVERS)",
                          icon: Icons.inventory_2_outlined,
                          color: Colors.purple,
                          count: _leftoverMaterials.length,
                          children: _buildLeftoversList(),
                        ),

                        _buildCollapsibleSection(
                          title: "TOTAL MATERIALS RECEIVED (IN)",
                          icon: Icons.download_rounded,
                          color: Colors.orange,
                          count: _materialsIn.length,
                          children: _buildMapList(_materialsIn, Colors.orange),
                        ),

                        _buildCollapsibleSection(
                          title: "TOTAL PRODUCTS DISPATCHED (OUT)",
                          icon: Icons.upload_rounded,
                          color: Colors.blue,
                          count: _productsOut.length,
                          children: _buildMapList(_productsOut, Colors.blue),
                        ),

                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // --- HELPER WIDGETS ---

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: Colors.grey[600],
          letterSpacing: 1,
        ),
      ),
    );
  }

  Widget _buildFinanceRow(
    String label,
    String amount,
    Color amountColor, {
    bool isTotal = false,
    String? subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: isTotal ? 16 : 14,
                    fontWeight: isTotal ? FontWeight.w900 : FontWeight.bold,
                    color: isTotal ? Colors.black87 : Colors.grey[800],
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey[500],
                      height: 1.5,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            amount,
            style: TextStyle(
              fontSize: isTotal ? 20 : 16,
              fontWeight: FontWeight.w900,
              color: amountColor,
            ),
          ),
        ],
      ),
    );
  }

  // 🔥 THE COLLAPSIBLE WIDGET 🔥
  Widget _buildCollapsibleSection({
    required String title,
    String? subtitle,
    required IconData icon,
    required Color color,
    required int count,
    double? totalAmount,
    required List<Widget> children,
  }) {
    final formatCurrency = NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 0,
    );

    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 12),
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          iconColor: color,
          collapsedIconColor: color,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          subtitle: subtitle != null
              ? Text(
                  subtitle,
                  style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                )
              : null,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (totalAmount != null)
                Text(
                  formatCurrency.format(totalAmount),
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    color: color,
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    "$count Items",
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[700],
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              Icon(Icons.keyboard_arrow_down_rounded, color: Colors.grey[400]),
            ],
          ),
          children: children.isEmpty
              ? [
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                      "No records found for this period.",
                      style: TextStyle(
                        color: Colors.grey,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ]
              : children,
        ),
      ),
    );
  }

  Future<void> _editScrapOrDiscount(Map<String, dynamic> data) async {
    TextEditingController amountCtrl = TextEditingController(
      text: data['amount'].toString(),
    );
    DateTime selectedDate =
        DateTime.tryParse(data['transaction_date'] ?? data['date'] ?? '') ??
        DateTime.now();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text("✏️ Edit Record"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: "Amount"),
              ),
              const SizedBox(height: 10),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text("Transaction Date"),
                subtitle: Text(DateFormat('dd MMM yyyy').format(selectedDate)),
                trailing: const Text("✏️"),
                onTap: () async {
                  DateTime? picked = await showDatePicker(
                    context: context,
                    initialDate: selectedDate,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) {
                    setDialogState(() => selectedDate = picked);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("CANCEL"),
            ),
            ElevatedButton(
              onPressed: () async {
                double newAmt = double.tryParse(amountCtrl.text) ?? 0.0;
                if (data['payment_id'] != null) {
                  await DatabaseHelper.instance.updatePaymentRecord(
                    data['payment_id'],
                    newAmt,
                    selectedDate.toIso8601String(),
                  );
                  Navigator.pop(context);
                  _fetchSummaryData();
                }
              },
              child: const Text("SAVE"),
            ),
          ],
        ),
      ),
    );
  }

  // --- LIST BUILDERS FOR THE COLLAPSIBLE SECTIONS ---

  // Builder for Discounts & Scrap Value Lists
  List<Widget> _buildAdjustmentList(
    List<Map<String, dynamic>> items,
    Color color,
    String adjustmentName,
  ) {
    final formatCurrency = NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 0,
    );
    return items.map((data) {
      DateTime deductDate =
          DateTime.tryParse(data['transaction_date'] ?? data['date'] ?? '') ??
          DateTime.now();
      DateTime billDate =
          DateTime.tryParse(data['bill_date'] ?? data['date'] ?? '') ??
          deductDate;

      String formattedDeduct = DateFormat('dd-MMM-yyyy').format(deductDate);
      String formattedBill = DateFormat('dd-MMM-yyyy').format(billDate);

      return Column(
        children: [
          const Divider(height: 1),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 4,
            ),
            title: Text(
              data['client_name'],
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            subtitle: Text(
              "Bill #${data['bill_no']}\nDeducted: $formattedDeduct | Bill Date: $formattedBill",
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[600],
                height: 1.5,
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (data['payment_id'] != null)
                  InkWell(
                    onTap: () => _editScrapOrDiscount(data),
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8.0,
                        vertical: 4.0,
                      ),
                      child: Text(
                        "✏️ Edit",
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue[700],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(width: 4),
                Text(
                  "- ${formatCurrency.format(data['amount'])}",
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: color,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }).toList();
  }

  List<Widget> _buildDetailedClientPaymentsList() {
    final formatCurrency = NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 0,
    );

    return _clientPaymentsList.map((p) {
      DateTime date =
          DateTime.tryParse(p['payment_date'] ?? '') ?? DateTime.now();
      String note = (p['notes'] ?? 'Payment').toString().trim();
      if (note.isEmpty) note = "Payment";

      return Column(
        children: [
          const Divider(height: 1),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 4,
            ),
            title: Text(
              p['client_name'] ?? 'Unknown Client',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            subtitle: Text(
              "$note • Bill #${p['bill_no']}\n${DateFormat('dd MMM yyyy, hh:mm a').format(date)}",
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[600],
                height: 1.5,
              ),
            ),
            trailing: Text(
              "+ ${formatCurrency.format(p['amount'])}",
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 14,
                color: Colors.green[700],
              ),
            ),
          ),
        ],
      );
    }).toList();
  }

  List<Widget> _buildDetailedWorkerPaymentsList() {
    final formatCurrency = NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 0,
    );

    return _workerPaymentsList.map((w) {
      DateTime date = DateTime.tryParse(w['paid_date'] ?? '') ?? DateTime.now();

      return Column(
        children: [
          const Divider(height: 1),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 4,
            ),
            title: Text(
              w['worker_name'] ?? 'Unknown Worker',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            subtitle: Text(
              "Wage / Advance Payout\n${DateFormat('dd MMM yyyy, hh:mm a').format(date)}",
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[600],
                height: 1.5,
              ),
            ),
            trailing: Text(
              "- ${formatCurrency.format(w['amount'])}",
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 14,
                color: Colors.red[700],
              ),
            ),
          ),
        ],
      );
    }).toList();
  }

  List<Widget> _buildClientDuesList() {
    final formatCurrency = NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 0,
    );

    return _clientDues.map((data) {
      DateTime date = DateTime.parse(data['date']);
      return Column(
        children: [
          const Divider(height: 1),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 4,
            ),
            title: Text(
              data['client_name'],
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            subtitle: Text(
              "Bill #${data['bill_no']} • ${DateFormat('dd MMM yyyy').format(date)}${data['phone'] != null ? '\nPh: ${data['phone']}' : ''}",
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[600],
                height: 1.5,
              ),
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  "PENDING",
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: Colors.red[300],
                  ),
                ),
                Text(
                  formatCurrency.format(data['due']),
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Colors.red[700],
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }).toList();
  }

  List<Widget> _buildLeftoversList() {
    return _leftoverMaterials.map((data) {
      List<String> leftovers = List<String>.from(data['leftovers']);
      DateTime date = DateTime.parse(data['date']);

      return Column(
        children: [
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      data['client_name'],
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      DateFormat('dd MMM yyyy').format(date),
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  "Bill #${data['bill_no']} • Status: ${data['status']}",
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.blue[700],
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: leftovers.map((item) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange[50],
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.orange[200]!),
                      ),
                      child: Text(
                        item,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange[900],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ],
      );
    }).toList();
  }

  List<Widget> _buildMapList(Map<String, int> items, Color color) {
    return items.entries.map((e) {
      return Column(
        children: [
          const Divider(height: 1),
          ListTile(
            dense: true,
            title: Text(
              e.key,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            trailing: Text(
              e.value.toString(),
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 14,
                color: color,
              ),
            ),
          ),
        ],
      );
    }).toList();
  }
}
