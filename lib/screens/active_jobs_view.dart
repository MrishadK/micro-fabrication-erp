import 'dart:convert'; // 🔥 Added so we can read item names safely
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import '../providers.dart';
import '../widgets/job_card_mobile.dart';
import '../services/ai_auditor_service.dart';
import '../database_helper.dart';
import '../widgets/edit_job_dialog.dart';

class ActiveJobsView extends ConsumerStatefulWidget {
  const ActiveJobsView({super.key});

  @override
  ConsumerState<ActiveJobsView> createState() => _ActiveJobsViewState();
}

class _ActiveJobsViewState extends ConsumerState<ActiveJobsView> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = "";
  int _sortOption = 0; // 0 = Newest, 1 = Oldest, 2 = Name A-Z
  String _statusFilter = 'All'; // Current status filter
  bool _showDone = false;

  Map<String, dynamic>? _aiAlertData;
  bool _isAiChecking = false;

  Future<void> _checkAi() async {
    HapticFeedback.lightImpact();
    setState(() => _isAiChecking = true);
    final alert = await AiAuditorService.runAudit();
    setState(() {
      _isAiChecking = false;
      _aiAlertData = alert;
    });

    if (alert != null) {
      _showAiAlert();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("✨ Data looks good! No anomalies found."),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            backgroundColor: Colors.green[700],
          ),
        );
      }
    }
  }

  void _showAiAlert() {
    if (_aiAlertData == null) return;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.auto_awesome,
                    color: Colors.purple,
                    size: 28,
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    "AI Data Auditor",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.purple,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (_aiAlertData!['type'] == 'job') ...[
                Text(
                  "Client: ${_aiAlertData!['client_name']}",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text("Bill Date: ${_aiAlertData!['created_at']}"),
              ] else if (_aiAlertData!['type'] == 'worker') ...[
                Text(
                  "Worker ID: ${_aiAlertData!['worker_id']}",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text("Date: ${_aiAlertData!['date']}"),
              ],
              const SizedBox(height: 15),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red[200]!),
                ),
                child: Text(
                  _aiAlertData!['message'],
                  style: TextStyle(color: Colors.red[900], fontSize: 14),
                ),
              ),
              const SizedBox(height: 20),
              if (_aiAlertData!['type'] == 'job')
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      final db = await DatabaseHelper.instance.database;
                      final res = await db.query(
                        'jobs',
                        where: 'id = ?',
                        whereArgs: [_aiAlertData!['job_id']],
                      );
                      if (res.isNotEmpty && mounted) {
                        showDialog(
                          context: context,
                          builder: (c) => EditJobDialog(job: res.first),
                        );
                      }
                    },
                    icon: const Icon(Icons.edit),
                    label: const Text("Edit Record"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue[700],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              Center(
                child: Text(
                  "(AI can only read data, not edit. Please review manually.)",
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey[600],
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  final NumberFormat _currencyFormat = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );

  // Available statuses for filtering
  final List<String> _statuses = ['All', 'Nothing', 'Ongoing', 'Ready', 'Done'];

  // Icons for each status
  final Map<String, IconData> _statusIcons = {
    'All': Icons.apps,
    'Nothing': Icons.pending_actions,
    'Ongoing': Icons.sync,
    'Ready': Icons.check_circle_outline,
    'Done': Icons.done_all,
  };

  // Colors for each status
  final Map<String, Color> _statusColors = {
    'All': Colors.white,
    'Nothing': Colors.grey,
    'Ongoing': Colors.orange,
    'Ready': Colors.lightBlue,
    'Done': Colors.green,
  };

  @override
  Widget build(BuildContext context) {
    final jobsAsync = ref.watch(activeJobsProvider);

    return Column(
      children: [
        // --- APP BAR AREA ---
        Container(
          padding: const EdgeInsets.only(
            top: 50,
            left: 20,
            right: 20,
            bottom: 20,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFF1A237E),
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(25),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF1A237E).withOpacity(0.3),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Dashboard",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Row(
                    children: [
                      // --- AI BUTTON ---
                      _isAiChecking
                          ? const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16.0),
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  color: Colors.purpleAccent,
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : IconButton(
                              icon: const Icon(
                                Icons.auto_awesome,
                                color: Colors.purpleAccent,
                              ),
                              tooltip: "Run AI Audit",
                              onPressed: _checkAi,
                            ),
                      // --- SORTING BUTTON ---
                      PopupMenuButton<int>(
                        icon: const Icon(
                          Icons.sort_rounded,
                          color: Colors.white,
                        ),
                        tooltip: "Sort Jobs",
                        onSelected: (int value) {
                          setState(() => _sortOption = value);
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(
                            value: 0,
                            child: Text("📅 Newest First"),
                          ),
                          PopupMenuItem(
                            value: 1,
                            child: Text("📅 Oldest First"),
                          ),
                          PopupMenuItem(
                            value: 2,
                            child: Text("🔤 Client Name (A-Z)"),
                          ),
                        ],
                      ),
                      // --- SHOW/HIDE DONE ICON ---
                      IconButton(
                        icon: Icon(
                          _showDone ? Icons.visibility : Icons.visibility_off,
                          color: _showDone
                              ? Colors.greenAccent
                              : Colors.white70,
                        ),
                        onPressed: () => setState(() => _showDone = !_showDone),
                        tooltip: "Toggle Completed Jobs",
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 15),

              // --- SEARCH BAR ---
              TextField(
                controller: _searchCtrl,
                onChanged: (val) =>
                    setState(() => _searchQuery = val.toLowerCase()),
                style: const TextStyle(color: Colors.black87),
                decoration: InputDecoration(
                  hintText:
                      "Search #bill, name, item...", // 🔥 Updated Hint                  hintStyle: TextStyle(color: Colors.grey[500], fontSize: 14),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: Colors.grey,
                  ),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(
                            Icons.clear,
                            size: 18,
                            color: Colors.grey,
                          ),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _searchQuery = "");
                            FocusScope.of(context).unfocus();
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 15),

              // --- STATUS FILTER CHIPS ---
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  children: _statuses
                      .map((status) => _buildFilterChip(status))
                      .toList(),
                ),
              ),
            ],
          ),
        ),

        // --- JOB LIST & DYNAMIC TOTAL ---
        Expanded(
          child: jobsAsync.when(
            data: (allJobs) {
              // 1. Apply filters
              Iterable<Map<String, dynamic>> filteredItems = allJobs.where((j) {
                if (_statusFilter != 'All' && j['status'] != _statusFilter) {
                  return false;
                }
                if (!_showDone &&
                    j['status'] == 'Done' &&
                    _statusFilter != 'Done') {
                  return false;
                }
                if (_searchQuery.isNotEmpty) {
                  final q = _searchQuery.trim();

                  // 🔥 NEW: EXCLUSIVE BILL NUMBER SEARCH 🔥
                  // If they type "#123", we ONLY check the bill number!
                  if (q.startsWith('#')) {
                    final targetBill = q.substring(1).trim(); // Removes the '#'
                    final bNo = (j['bill_no'] ?? '').toString().toLowerCase();
                    return bNo.contains(targetBill);
                  }

                  // 🔥 STANDARD SEARCH 🔥
                  // We removed bNo from here so typing "555" won't accidentally pull up Bill #555
                  final cName = (j['client_name'] ?? '')
                      .toString()
                      .toLowerCase();
                  final cPhone = (j['client_phone'] ?? '')
                      .toString()
                      .toLowerCase();
                  final mBrought = (j['material_brought'] ?? '')
                      .toString()
                      .toLowerCase();
                  final pType = (j['product_type'] ?? '')
                      .toString()
                      .toLowerCase();

                  bool isMatch =
                      cName.contains(q) ||
                      cPhone.contains(q) ||
                      mBrought.contains(q) ||
                      pType.contains(q);

                  // Safely search inside the items JSON for actual item names
                  if (!isMatch &&
                      j['items'] != null &&
                      j['items'].toString().startsWith('{')) {
                    try {
                      final data = jsonDecode(j['items']);
                      final inList = data['in'] as List? ?? [];
                      final outList = data['out'] as List? ?? [];

                      for (var item in inList) {
                        if ((item['name']?.toString() ?? '')
                            .toLowerCase()
                            .contains(q)) {
                          isMatch = true;
                          break;
                        }
                      }
                      if (!isMatch) {
                        for (var item in outList) {
                          if ((item['name']?.toString() ?? '')
                              .toLowerCase()
                              .contains(q)) {
                            isMatch = true;
                            break;
                          }
                        }
                      }
                    } catch (_) {}
                  }

                  return isMatch;
                }
                return true;
              });

              // 2. Apply sorting
              List<Map<String, dynamic>> jobs = filteredItems.toList();
              jobs.sort((a, b) {
                switch (_sortOption) {
                  case 0:
                    return b['created_at'].compareTo(a['created_at']);
                  case 1:
                    return a['created_at'].compareTo(b['created_at']);
                  case 2:
                    return (a['client_name'] ?? "").compareTo(
                      b['client_name'] ?? "",
                    );
                  default:
                    return 0;
                }
              });

              // 3. Calculate totals for visible jobs
              double currentTotalCost = 0.0;
              double currentTotalPaid = 0.0;
              for (var j in jobs) {
                currentTotalCost += (j['total_cost'] as num?)?.toDouble() ?? 0;
                currentTotalPaid += (j['paid_sum'] as num?)?.toDouble() ?? 0;
              }
              double currentPending = currentTotalCost - currentTotalPaid;

              if (jobs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.search_off_rounded,
                        size: 80,
                        color: Colors.grey[300],
                      ),
                      const SizedBox(height: 15),
                      Text(
                        "No jobs found",
                        style: TextStyle(fontSize: 16, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                );
              }

              return Column(
                children: [
                  // 🔥 PREMIUM DYNAMIC TOTAL HEADER 🔥
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 20,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F4F8),
                      border: Border(
                        bottom: BorderSide(color: Colors.blueGrey.shade100),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "${jobs.length} ${_statusFilter == 'All' ? 'Jobs' : '$_statusFilter Jobs'}",
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Color(0xFF455A64),
                            letterSpacing: 0.5,
                          ),
                        ),
                        if (currentPending > 0)
                          Row()
                        else if (currentTotalCost > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green[100],
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              "Fully Paid",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.green[800],
                                fontSize: 11,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  // SCROLLABLE LIST
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: () async => ref.refresh(activeJobsProvider),
                      child: ListView.builder(
                        padding: const EdgeInsets.only(top: 10, bottom: 90),
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: jobs.length,
                        itemBuilder: (ctx, i) =>
                            JobCardMobile(job: jobs[i], ref: ref),
                      ),
                    ),
                  ),
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, s) => Center(child: Text("Error: $e")),
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChip(String status) {
    final bool isSelected = _statusFilter == status;
    final Color baseColor = _statusColors[status]!;

    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: InkWell(
        onTap: () => setState(() => _statusFilter = status),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? baseColor.withOpacity(0.2)
                : Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? baseColor : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _statusIcons[status],
                size: 14,
                color: isSelected ? baseColor : Colors.white70,
              ),
              const SizedBox(width: 6),
              Text(
                status,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? baseColor : Colors.white70,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
