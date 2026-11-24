import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:micro/database_helper.dart';
import '../providers.dart';
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/pdf_service.dart';

class HistoryView extends ConsumerStatefulWidget {
  const HistoryView({super.key});

  @override
  ConsumerState<HistoryView> createState() => _HistoryViewState();
}

class _HistoryViewState extends ConsumerState<HistoryView> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _localSearchQuery = "";
  int _sortOption = 0;

  final Color _primaryColor = const Color(0xFF1A237E);

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String _parseItemsSummary(String? itemsJson) {
    if (itemsJson == null || itemsJson.isEmpty) return "No items";
    try {
      final dynamic decoded = jsonDecode(itemsJson);
      if (decoded is Map<String, dynamic>) {
        final List<dynamic> outList = decoded['out'] ?? [];
        if (outList.isNotEmpty) {
          final firstItem = outList[0];
          final count = outList.length;
          return "${firstItem['name']} (x${firstItem['qty']})" +
              (count > 1 ? " + ${count - 1} more" : "");
        }
      }
      return "View details";
    } catch (e) {
      return "View details";
    }
  }

  String _formatCurrency(num value) {
    return NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 0,
    ).format(value);
  }

  List<Map<String, dynamic>> _processJobs(List<Map<String, dynamic>> jobs) {
    // 1. First, apply search filter
    var filtered = jobs.where((job) {
      if (_localSearchQuery.isEmpty) return true;
      final total = (job['total_cost'] as num?) ?? 0;
      final paid = (job['paid_sum'] as num?) ?? 0;

      // 🔥 NEW: Search can now recognize estimates vs paid
      String statusText;
      if (total == 0) {
        statusText = "estimate";
      } else if ((total - paid) > 1) {
        statusText = "due";
      } else {
        statusText = "paid";
      }

      final dDate = job['completed_at'] != null
          ? DateTime.parse(job['completed_at'])
          : DateTime.parse(job['created_at']);
      final dateStr = DateFormat('dd-MMM-yyyy').format(dDate).toLowerCase();

      final searchStr =
          "${job['id']} ${job['client_name']} ${job['items']} $dateStr $statusText"
              .toLowerCase();
      return searchStr.contains(_localSearchQuery);
    }).toList();

    // 2. Apply Payment Status Filter (Options 4, 5, 6)
    if (_sortOption == 4) {
      // DUE Only
      filtered = filtered.where((job) {
        final total = (job['total_cost'] as num?) ?? 0;
        final paid = (job['paid_sum'] as num?) ?? 0;
        return (total - paid) > 1;
      }).toList();
    } else if (_sortOption == 5) {
      // PAID Only (Excludes Estimates)
      filtered = filtered.where((job) {
        final total = (job['total_cost'] as num?) ?? 0;
        final paid = (job['paid_sum'] as num?) ?? 0;
        return (total - paid) <= 1 && total > 0;
      }).toList();
    } else if (_sortOption == 6) {
      // 🔥 NEW: ESTIMATES Only
      filtered = filtered.where((job) {
        final total = (job['total_cost'] as num?) ?? 0;
        return total == 0;
      }).toList();
    }

    // 3. Apply Date/Value Sorting (Options 0 to 3)
    filtered.sort((a, b) {
      final aDate = a['completed_at'] != null
          ? a['completed_at']
          : a['created_at'];
      final bDate = b['completed_at'] != null
          ? b['completed_at']
          : b['created_at'];

      switch (_sortOption) {
        case 0:
        case 4: // Default sort for Due
        case 5: // Default sort for Paid
        case 6: // Default sort for Estimates
          return bDate.compareTo(aDate);
        case 1:
          return aDate.compareTo(bDate);
        case 2:
          return (b['total_cost'] as num).compareTo(a['total_cost'] as num);
        case 3:
          return (a['total_cost'] as num).compareTo(b['total_cost'] as num);
        default:
          return 0;
      }
    });
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final historyAsync = ref.watch(historyJobsProvider);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Color(0xFF1A237E),
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        body: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: historyAsync.when(
                data: (jobs) {
                  final processedJobs = _processJobs(jobs);
                  if (processedJobs.isEmpty) return _buildEmptyState();

                  return RefreshIndicator(
                    onRefresh: () async {
                      HapticFeedback.lightImpact();
                      ref.read(dbRefreshTriggerProvider.notifier).state++;
                    },
                    color: _primaryColor,
                    child: ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                      itemCount: processedJobs.length,
                      itemBuilder: (context, index) =>
                          _buildJobCard(processedJobs[index]),
                    ),
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, s) => Center(child: Text("Error: $e")),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.only(top: 50, left: 20, right: 20, bottom: 25),
      decoration: BoxDecoration(
        color: _primaryColor,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(30)),
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
            children: [
              const Text(
                "History Archive",
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: PopupMenuButton<int>(
                  icon: const Icon(Icons.sort_rounded, color: Colors.white),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  color: Colors.white,
                  elevation: 8,
                  offset: const Offset(0, 40),
                  onSelected: (val) {
                    HapticFeedback.lightImpact();
                    setState(() => _sortOption = val);
                  },
                  itemBuilder: (context) => [
                    _buildSortMenuItem(
                      0,
                      "Delivery: Newest First",
                      Icons.arrow_downward_rounded,
                    ),
                    _buildSortMenuItem(
                      1,
                      "Delivery: Oldest First",
                      Icons.arrow_upward_rounded,
                    ),
                    const PopupMenuDivider(),
                    _buildSortMenuItem(
                      4,
                      "Show DUE Only",
                      Icons.warning_amber_rounded,
                      color: Colors.red[700],
                    ),
                    _buildSortMenuItem(
                      5,
                      "Show PAID Only",
                      Icons.check_circle_outline_rounded,
                      color: Colors.green[700],
                    ),
                    _buildSortMenuItem(
                      6,
                      "Show ESTIMATES",
                      Icons.receipt_long_rounded,
                      color: Colors.orange[700],
                    ),
                    const PopupMenuDivider(),
                    _buildSortMenuItem(
                      2,
                      "Value: High-Low",
                      Icons.monetization_on_outlined,
                    ),
                    _buildSortMenuItem(
                      3,
                      "Value: Low-High",
                      Icons.money_off_outlined,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _searchCtrl,
            style: const TextStyle(color: Colors.black87),
            onChanged: (val) =>
                setState(() => _localSearchQuery = val.toLowerCase()),
            decoration: InputDecoration(
              hintText: "Search Bill #, Client, Phone...",
              hintStyle: TextStyle(color: Colors.grey[500], fontSize: 14),
              prefixIcon: Icon(Icons.search_rounded, color: _primaryColor),
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
              suffixIcon: _localSearchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      color: Colors.grey,
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _localSearchQuery = "");
                      },
                    )
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  PopupMenuItem<int> _buildSortMenuItem(
    int value,
    String text,
    IconData icon, {
    Color? color,
  }) {
    final isSelected = _sortOption == value;
    final primary = color ?? _primaryColor;
    return PopupMenuItem<int>(
      value: value,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected ? primary : Colors.grey[500],
            ),
            const SizedBox(width: 12),
            Text(
              text,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? primary : Colors.grey[800],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.history_toggle_off_rounded,
            size: 80,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 15),
          Text(
            "No records found",
            style: TextStyle(fontSize: 16, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildJobCard(Map<String, dynamic> job) {
    final total = (job['total_cost'] as num?)?.toDouble() ?? 0.0;
    final advance = (job['advance_paid'] as num?)?.toDouble() ?? 0.0;
    final paid = (job['paid_sum'] as num?)?.toDouble() ?? 0.0;
    final discount = (job['discount'] as num?)?.toDouble() ?? 0.0;
    final scrap = (job['scrap_value'] as num?)?.toDouble() ?? 0.0;
    final rawBal = total - (advance + paid) - discount - scrap;
    final balance = rawBal;
    final dDate = job['completed_at'] != null
        ? DateTime.parse(job['completed_at'])
        : DateTime.parse(job['created_at']);
    final dateStr = "Delivered: " + DateFormat('dd MMM yyyy').format(dDate);

    final String displayBillNo =
        (job['bill_no'] != null && job['bill_no'].toString().trim().isNotEmpty)
        ? job['bill_no'].toString()
        : job['id'].toString();

    final String name = job['client_name'] ?? "Unknown";
    final String initials = name.isNotEmpty ? name[0].toUpperCase() : "?";

    // 🔥 SMART BALANCE LABEL LOGIC 🔥
    String balLabel;
    Color balBg;
    Color balText;

    if (total == 0) {
      balLabel = "ESTIMATE";
      balBg = Colors.orange[50]!;
      balText = Colors.orange[800]!;
    } else if (balance < 0) {
      balLabel = "CREDIT";
      balBg = Colors.blue[50]!;
      balText = Colors.blue[700]!;
    } else if (balance > 1) {
      balLabel = "DUE";
      balBg = Colors.red[50]!;
      balText = Colors.red[700]!;
    } else {
      balLabel = "PAID";
      balBg = Colors.green[50]!;
      balText = Colors.green[700]!;
    }

    // --- CALCULATE REMAINING MATERIALS FOR BADGE ---
    List<dynamic> materials = [];
    List<dynamic> products = [];

    if (job['items'] != null && job['items'].toString().startsWith('{')) {
      try {
        final data = jsonDecode(job['items']);
        materials = data['in'] ?? [];
        products = data['out'] ?? [];
      } catch (_) {}
    }

    if (materials.isEmpty &&
        job['material_brought'] != null &&
        job['material_brought'].toString().isNotEmpty) {
      materials.add({'name': job['material_brought'], 'qty': job['qty_given']});
    }
    if (products.isEmpty &&
        job['product_type'] != null &&
        job['product_type'].toString().isNotEmpty) {
      products.add({'name': job['product_type'], 'qty': job['target_qty']});
    }

    List<String> remainingMats = [];
    for (var mat in materials) {
      String matId = mat['id']?.toString() ?? '';
      String matName = mat['name']?.toString() ?? 'Unknown';
      int totalQty = (mat['qty'] as num?)?.toInt() ?? 0;

      int used = 0;
      for (var prod in products) {
        List links = prod['linked_materials'] ?? [];
        if (links.isEmpty && prod['linked_ids'] != null) {
          links = (prod['linked_ids'] as List)
              .map((id) => {'id': id, 'used_qty': 1})
              .toList();
        }

        for (var link in links) {
          if (link['id'] == matId) {
            used += (link['used_qty'] as num?)?.toInt() ?? 0;
          }
        }
      }

      int rem = totalQty - used;
      if (rem > 0) {
        remainingMats.add("$matName: $rem");
      }
    }
    String remainingText = remainingMats.isEmpty
        ? "All Materials Used"
        : "Rem: ${remainingMats.join(', ')}";

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
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
            final isDesktop = MediaQuery.of(context).size.width >= 750;
            if (isDesktop) {
              await showDialog(
                context: context,
                builder: (context) => Dialog(
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  shadowColor: Colors.transparent,
                  surfaceTintColor: Colors.transparent,
                  insetPadding: EdgeInsets.symmetric(
                    horizontal:
                        MediaQuery.of(context).size.width > 900 ? 40 : 16,
                    vertical: 24,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: 900,
                        maxHeight: MediaQuery.of(context).size.height * 0.92,
                      ),
                      child: ExcludeSemantics(
                        child: JobDetailScreen(
                          job: job,
                          ref: ref,
                          isDialog: true,
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
                  builder: (context) => JobDetailScreen(job: job, ref: ref),
                ),
              );
            }
            ref.read(dbRefreshTriggerProvider.notifier).state++;
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: _primaryColor.withOpacity(0.08),
                  child: Text(
                    initials,
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
                          Flexible(
                            child: Text(
                              name,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF2d3436),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.grey[300]!),
                            ),
                            child: Text(
                              "#$displayBillNo",
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey[600],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _parseItemsSummary(job['items']),
                        style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),

                      // --- REMAINING MATERIALS BADGE ---
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: remainingMats.isEmpty
                              ? Colors.green.withOpacity(0.1)
                              : Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              remainingMats.isEmpty
                                  ? Icons.check_circle_outline
                                  : Icons.inventory_2_outlined,
                              size: 10,
                              color: Colors.black,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                remainingText,
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            Icons.calendar_today_rounded,
                            size: 12,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            dateStr,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (balance > 1) ...[
                      Text(
                        _formatCurrency(balance),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: Colors.red[800],
                        ),
                      ),
                      Text(
                        "/ ${_formatCurrency(total)}",
                        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                      ),
                    ] else
                      Text(
                        _formatCurrency(total),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF2d3436),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: balBg,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: balText.withOpacity(0.2)),
                      ),
                      child: Text(
                        balLabel,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: balText,
                          letterSpacing: 0.5,
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
}

// ==========================================
//          DETAIL SCREEN
// ==========================================
class JobDetailScreen extends StatefulWidget {
  final Map<String, dynamic> job;
  final WidgetRef ref;
  final bool isDialog;

  const JobDetailScreen({
    super.key,
    required this.job,
    required this.ref,
    this.isDialog = false,
  });

  @override
  State<JobDetailScreen> createState() => _JobDetailScreenState();
}

class _JobDetailScreenState extends State<JobDetailScreen> {
  late Map<String, dynamic> currentJob;
  final PdfService _pdf = PdfService();

  @override
  void initState() {
    super.initState();
    currentJob = Map<String, dynamic>.from(widget.job);
  }

  Future<void> _refreshJob() async {
    final db = await DatabaseHelper.instance.database;
    final res = await db.rawQuery(
      '''
      SELECT j.*,
             (SELECT COALESCE(SUM(amount), 0) FROM payments WHERE job_id = j.id) as paid_sum
      FROM jobs j
      WHERE j.id = ?
      LIMIT 1
    ''',
      [widget.job['id']],
    );
    if (res.isNotEmpty) {
      setState(() {
        currentJob = Map<String, dynamic>.from(res.first);
      });
      widget.ref.read(dbRefreshTriggerProvider.notifier).state++;
    }
  }

  Future<void> _editBillDetails() async {
    TextEditingController notesCtrl = TextEditingController(
      text: currentJob['work_details'] ?? '',
    );
    DateTime orderDate =
        DateTime.tryParse(currentJob['created_at'] ?? '') ?? DateTime.now();
    DateTime? deliveryDate = currentJob['completed_at'] != null
        ? DateTime.tryParse(currentJob['completed_at'])
        : null;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Container(
            padding: const EdgeInsets.all(18),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1A237E), Color(0xFF3949AB)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.edit_calendar_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Edit Bill Details",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        "Manage Order & Delivery Dates",
                        style: TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          titlePadding: EdgeInsets.zero,
          contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: notesCtrl,
                  decoration: InputDecoration(
                    labelText: "Notes & Job Details",
                    labelStyle: const TextStyle(
                      color: Color(0xFF1A237E),
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                    hintText:
                        "Add specific instructions, delivery notes, or details...",
                    hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
                    filled: true,
                    fillColor: Colors.grey[50],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: Color(0xFF1A237E),
                        width: 1.5,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    contentPadding: const EdgeInsets.all(16),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          DateTime? picked = await showDatePicker(
                            context: context,
                            initialDate: orderDate,
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) {
                            setDialogState(() => orderDate = picked);
                          }
                        },
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 16,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEBF3FF),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: const Color(0xFF90CAF9),
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.blue.withOpacity(0.04),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: const BoxDecoration(
                                      color: Colors.blue,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.calendar_today_rounded,
                                      size: 10,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  const Text(
                                    "ORDER DATE",
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.blue,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                DateFormat('dd MMM yyyy').format(orderDate),
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF0D47A1),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          DateTime? picked = await showDatePicker(
                            context: context,
                            initialDate: deliveryDate ?? DateTime.now(),
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) {
                            setDialogState(() => deliveryDate = picked);
                          }
                        },
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 16,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8F5E9),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: const Color(0xFFA5D6A7),
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.green.withOpacity(0.04),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: const BoxDecoration(
                                      color: Colors.green,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.local_shipping_rounded,
                                      size: 10,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  const Text(
                                    "DELIVERED",
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.green,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                deliveryDate != null
                                    ? DateFormat(
                                        'dd MMM yyyy',
                                      ).format(deliveryDate!)
                                    : "Not Shipped",
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: deliveryDate != null
                                      ? const Color(0xFF1B5E20)
                                      : Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (deliveryDate != null) ...[
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.red[700],
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: const Icon(
                        Icons.remove_circle_outline_rounded,
                        size: 14,
                      ),
                      label: const Text(
                        "Set as Undelivered",
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onPressed: () =>
                          setDialogState(() => deliveryDate = null),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          actions: [
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: Colors.grey[700],
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () => Navigator.pop(context),
              child: const Text(
                "Cancel",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A237E),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 2,
                shadowColor: const Color(0xFF1A237E).withOpacity(0.4),
              ),
              icon: const Icon(Icons.save_rounded, size: 18),
              label: const Text(
                "Save Changes",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              onPressed: () async {
                await DatabaseHelper.instance.updateBillDetails(
                  currentJob['id'],
                  orderDate.toIso8601String(),
                  deliveryDate?.toIso8601String(),
                  notesCtrl.text,
                );
                Navigator.pop(context);
                _refreshJob();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editJobAmount(
    String title,
    double currentAmount,
    bool isAdvance,
  ) async {
    TextEditingController amountCtrl = TextEditingController(
      text: currentAmount.toString(),
    );
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("✏️ Edit $title"),
        content: TextField(
          controller: amountCtrl,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: "New $title Amount"),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CANCEL"),
          ),
          ElevatedButton(
            onPressed: () async {
              double newAmt = double.tryParse(amountCtrl.text) ?? 0.0;
              if (isAdvance) {
                await DatabaseHelper.instance.updateJobAdvance(
                  currentJob['id'],
                  newAmt,
                );
              } else {
                await DatabaseHelper.instance.updateJobScrap(
                  currentJob['id'],
                  newAmt,
                );
              }
              Navigator.pop(context);
              _refreshJob();
            },
            child: const Text("SAVE"),
          ),
        ],
      ),
    );
  }

  String _cleanPhone(dynamic raw) {
    if (raw == null) return "";
    String s = raw.toString().trim();
    if (s.endsWith('.0')) {
      s = s.substring(0, s.length - 2);
    }
    return s;
  }

  void _showCallDialog(BuildContext context) {
    HapticFeedback.lightImpact();
    final clientName = (currentJob['client_name'] as String?)?.trim() ?? 'Client';
    final clientPlace = (currentJob['client_place'] as String?)?.trim() ?? '';
    final phone = _cleanPhone(currentJob['client_phone']);

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: Colors.white,
        clipBehavior: Clip.antiAlias,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: const BoxDecoration(
                        color: Color(0xFFDCFCE7),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.phone_in_talk_rounded,
                        color: Color(0xFF16A34A),
                        size: 22,
                      ),
                    ),
                    const Text(
                      "Client Contact",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 22),
                      color: const Color(0xFF64748B),
                      splashRadius: 20,
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  clientName.isNotEmpty ? clientName : "Unnamed Client",
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                    letterSpacing: -0.3,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (clientPlace.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.location_on_rounded,
                        size: 16,
                        color: Color(0xFF64748B),
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          clientPlace,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF475569),
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 20),
                if (phone.isNotEmpty) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      vertical: 20,
                      horizontal: 16,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFFE2E8F0),
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          "PHONE NUMBER",
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                            color: Color(0xFF64748B),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SelectableText(
                          phone,
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF0F172A),
                            letterSpacing: 1.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: phone));
                            HapticFeedback.lightImpact();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text("Phone number copied to clipboard!"),
                                backgroundColor: Color(0xFF1E293B),
                                behavior: SnackBarBehavior.floating,
                                duration: Duration(seconds: 2),
                              ),
                            );
                          },
                          icon: const Icon(Icons.copy_rounded, size: 18),
                          label: const Text(
                            "Copy",
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF334155),
                            side: const BorderSide(color: Color(0xFFCBD5E1)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            HapticFeedback.lightImpact();
                            final uri = Uri.parse("tel:$phone");
                            try {
                              if (await canLaunchUrl(uri)) {
                                await launchUrl(uri);
                              } else {
                                await Clipboard.setData(ClipboardData(text: phone));
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        "Number copied! (No dialer app available on this device)",
                                      ),
                                      backgroundColor: Color(0xFF1E293B),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                }
                              }
                            } catch (_) {
                              await Clipboard.setData(ClipboardData(text: phone));
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text("Number copied to clipboard!"),
                                    backgroundColor: Color(0xFF1E293B),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              }
                            }
                          },
                          icon: const Icon(Icons.call_rounded, size: 18),
                          label: const Text(
                            "Dial",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF16A34A),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFFCA5A5)),
                    ),
                    child: Row(
                      children: const [
                        Icon(
                          Icons.phone_disabled_rounded,
                          color: Color(0xFFDC2626),
                          size: 22,
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            "No phone number saved for this client.",
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF991B1B),
                            ),
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

  void _openPdfPreview({
    required BuildContext context,
    required bool isDetailed,
  }) {
    HapticFeedback.lightImpact();
    final sanitizedName = (currentJob['client_name'] ?? 'Client').toString().replaceAll(
      RegExp(r'[^\w\s]+'),
      '',
    ).trim();
    final billNo = (currentJob['bill_no'] != null && currentJob['bill_no'].toString().trim().isNotEmpty)
        ? currentJob['bill_no'].toString()
        : (currentJob['id']?.toString() ?? '1');
    final String prefix = isDetailed ? "Estimate" : "JobCard";
    final String docName = "${prefix}_${billNo}_$sanitizedName";
    final String title = isDetailed
        ? "Bill Preview (#$billNo - ${currentJob['client_name'] ?? 'Client'})"
        : "Job Card Preview (#$billNo - ${currentJob['client_name'] ?? 'Client'})";

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
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: SizedBox(
              width: dialogWidth,
              height: dialogHeight,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    color: const Color(0xFF1E293B),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.picture_as_pdf_rounded, color: Colors.white, size: 20),
                            const SizedBox(width: 10),
                            Text(
                              title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: Colors.white, size: 22),
                          splashRadius: 20,
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Container(
                      color: Colors.white,
                      child: PdfPreview(
                        build: (format) async => await _pdf.generateReceiptBytes(
                          currentJob,
                          isDetailed: isDetailed,
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
  }

  Future<void> _executeSharePdf({
    required BuildContext context,
    required bool isDetailed,
  }) async {
    HapticFeedback.lightImpact();
    try {
      final pdfBytes = await _pdf.generateReceiptBytes(
        currentJob,
        isDetailed: isDetailed,
      );
      final sanitizedName = (currentJob['client_name'] ?? 'Client').toString().replaceAll(
        RegExp(r'[^\w\s]+'),
        '',
      ).trim();
      final billNo = (currentJob['bill_no'] != null && currentJob['bill_no'].toString().trim().isNotEmpty)
          ? currentJob['bill_no'].toString()
          : (currentJob['id']?.toString() ?? '1');
      final String prefix = isDetailed ? "Estimate" : "JobCard";
      final String docName = "${prefix}_${billNo}_$sanitizedName";

      await Printing.sharePdf(
        bytes: pdfBytes,
        filename: '$docName.pdf',
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _printOrShareBill(BuildContext context) {
    HapticFeedback.lightImpact();
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: Colors.white,
        clipBehavior: Clip.antiAlias,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: const BoxDecoration(
                        color: Color(0xFFEEF2FF),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.print_rounded,
                        color: Color(0xFF4F46E5),
                        size: 22,
                      ),
                    ),
                    const Text(
                      "Print & Share",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 22),
                      color: const Color(0xFF64748B),
                      splashRadius: 20,
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  "Choose document format to print or share for ${currentJob['client_name'] ?? 'Client'}:",
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 16),

                // Option 1: Detailed Bill
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEFF6FF),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.receipt_long_rounded,
                              color: Color(0xFF2563EB),
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Detailed Bill",
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  "Includes payment records & leftover materials",
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.pop(ctx);
                                _openPdfPreview(
                                  context: context,
                                  isDetailed: true,
                                );
                              },
                              icon: const Icon(Icons.print_rounded, size: 16),
                              label: const Text(
                                "Print / Preview",
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF2563EB),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(vertical: 11),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Navigator.pop(ctx);
                                _executeSharePdf(
                                  context: context,
                                  isDetailed: true,
                                );
                              },
                              icon: const Icon(Icons.share_rounded, size: 16),
                              label: const Text("Share PDF"),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF1E293B),
                                side: const BorderSide(color: Color(0xFFCBD5E1)),
                                padding: const EdgeInsets.symmetric(vertical: 11),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Option 2: Simple Job Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF7ED),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.assignment_rounded,
                              color: Color(0xFFEA580C),
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Simple Job Card",
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  "Workshop ticket (hides costs, payments & leftovers)",
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.pop(ctx);
                                _openPdfPreview(
                                  context: context,
                                  isDetailed: false,
                                );
                              },
                              icon: const Icon(Icons.print_rounded, size: 16),
                              label: const Text(
                                "Print / Preview",
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFEA580C),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(vertical: 11),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Navigator.pop(ctx);
                                _executeSharePdf(
                                  context: context,
                                  isDetailed: false,
                                );
                              },
                              icon: const Icon(Icons.share_rounded, size: 16),
                              label: const Text("Share PDF"),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF1E293B),
                                side: const BorderSide(color: Color(0xFFCBD5E1)),
                                padding: const EdgeInsets.symmetric(vertical: 11),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ),
                        ],
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
  }

  @override
  Widget build(BuildContext context) {
    final String displayBillNo =
        (currentJob['bill_no'] != null &&
            currentJob['bill_no'].toString().trim().isNotEmpty)
        ? currentJob['bill_no'].toString()
        : currentJob['id'].toString();

    final total = (currentJob['total_cost'] as num?)?.toDouble() ?? 0.0;
    final advance = (currentJob['advance_paid'] as num?)?.toDouble() ?? 0.0;
    final paymentsSum = (currentJob['paid_sum'] as num?)?.toDouble() ?? 0.0;
    final totalPaid = advance + paymentsSum;
    final discount = (currentJob['discount'] as num?)?.toDouble() ?? 0.0;
    final scrap = (currentJob['scrap_value'] as num?)?.toDouble() ?? 0.0;
    final rawBalance = total - totalPaid - discount - scrap;
    final balance = rawBalance < 0 ? 0.0 : rawBalance;

    final orderedDate = DateTime.parse(currentJob['created_at']);
    final deliveredDate = currentJob['completed_at'] != null
        ? DateTime.parse(currentJob['completed_at'])
        : (currentJob['updated_at'] != null
              ? DateTime.parse(currentJob['updated_at'])
              : orderedDate);

    Map<String, dynamic> itemsData = {};
    try {
      itemsData = jsonDecode(currentJob['items'] ?? "{}");
    } catch (_) {}
    final List<dynamic> inList = itemsData['in'] ?? [];
    final List<dynamic> outList = itemsData['out'] ?? [];

    List<Map<String, dynamic>> matBalances = [];
    for (var mat in inList) {
      String matId = mat['id']?.toString() ?? '';
      String name = mat['name']?.toString() ?? 'Unknown';
      int totalQty = (mat['qty'] as num?)?.toInt() ?? 0;

      int used = 0;
      for (var prod in outList) {
        List links = prod['linked_materials'] ?? [];
        if (links.isEmpty && prod['linked_ids'] != null) {
          links = (prod['linked_ids'] as List)
              .map((id) => {'id': id, 'used_qty': 1})
              .toList();
        }
        for (var link in links) {
          if (link['id'] == matId) {
            used += (link['used_qty'] as num?)?.toInt() ?? 0;
          }
        }
      }
      matBalances.add({
        'name': name,
        'total': totalQty,
        'rem': totalQty - used,
      });
    }

    if (matBalances.isEmpty &&
        currentJob['material_brought'] != null &&
        currentJob['material_brought'].toString().isNotEmpty) {
      matBalances.add({
        'name': currentJob['material_brought'],
        'total': currentJob['qty_given'] ?? 0,
        'rem': 0,
      });
    }

    List<Widget> productionWidgets = _buildLinkedProductionView(
      inList,
      outList,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Color(0xFF1A237E),
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          leading: IconButton(
            icon: Icon(
              widget.isDialog
                  ? Icons.close_rounded
                  : Icons.arrow_back_rounded,
            ),
            tooltip: widget.isDialog ? 'Close' : 'Back',
            onPressed: () => Navigator.pop(context),
          ),
          title: Text("Bill #$displayBillNo"),
          backgroundColor: const Color(0xFF1A237E),
          foregroundColor: Colors.white,
          centerTitle: true,
          elevation: 0,
          actions: [
            TextButton.icon(
              onPressed: _editBillDetails,
              icon: const Text("✏️", style: TextStyle(fontSize: 14)),
              label: const Text(
                "Edit Bill",
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),

        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildInfoCard(
                title: "Client & Dates",
                content: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            currentJob['client_name'] ?? "Unknown",
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => _showCallDialog(context),
                          icon: const Icon(
                            Icons.phone_in_talk_rounded,
                            color: Color(0xFF16A34A),
                          ),
                          tooltip: "Call / Contact Client",
                        ),
                      ],
                    ),
                    const SizedBox(height: 15),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "Ordered On",
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                              Text(
                                DateFormat('dd MMM yyyy').format(orderedDate),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 30,
                          color: Colors.grey[300],
                        ),
                        const SizedBox(width: 15),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "Delivered On",
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.green,
                                ),
                              ),
                              Text(
                                DateFormat('dd MMM yyyy').format(deliveredDate),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 15),

              _buildInfoCard(
                title: "Raw Materials Inventory",
                content: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: matBalances.isEmpty
                      ? [const Text("-", style: TextStyle(color: Colors.grey))]
                      : matBalances.map((m) {
                          int rem = m['rem'];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.inventory_2_outlined,
                                        size: 16,
                                        color: Colors.orange[700],
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          m['name'],
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: Colors.grey[300]!,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        "Total: ${m['total']}",
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey[700],
                                        ),
                                      ),
                                      Container(
                                        width: 1,
                                        height: 12,
                                        color: Colors.grey[400],
                                        margin: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                        ),
                                      ),
                                      Text(
                                        "Rem: $rem",
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: rem > 0
                                              ? Colors.orange[800]
                                              : Colors.green[700],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                ),
              ),

              const SizedBox(height: 25),
              const Text(
                "Production Flow",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),

              if (productionWidgets.isEmpty)
                const Text(
                  "No items recorded.",
                  style: TextStyle(color: Colors.grey),
                )
              else
                ...productionWidgets,

              const Divider(thickness: 1, height: 40),

              const Text(
                "Assigned Workers",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              FutureBuilder<List<Map<String, dynamic>>>(
                future: DatabaseHelper.instance.getWorkersForJob(displayBillNo),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(20.0),
                        child: CircularProgressIndicator(),
                      ),
                    );
                  }

                  final workers = snapshot.data ?? [];

                  if (workers.isEmpty) {
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[200]!),
                      ),
                      child: const Text(
                        "No workers have been linked to this job yet.",
                        style: TextStyle(color: Colors.grey),
                        textAlign: TextAlign.center,
                      ),
                    );
                  }

                  double totalLaborCost = workers.fold(
                    0.0,
                    (sum, w) => sum + (w['total'] as num).toDouble(),
                  );

                  return Column(
                    children: [
                      ...workers.map((work) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.indigo.withOpacity(0.2),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.indigo.withOpacity(0.05),
                                blurRadius: 5,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              CircleAvatar(
                                backgroundColor: Colors.indigo.withOpacity(0.1),
                                child: const Icon(
                                  Icons.person,
                                  color: Colors.indigo,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          work['worker_name'],
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                          ),
                                        ),
                                        Text(
                                          DateFormat('dd MMM yyyy').format(
                                            DateTime.parse(work['date']),
                                          ),
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      "${work['task_name']}  •  ${work['qty']} pcs @ ₹${work['rate']}",
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey[800],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                "₹${work['total']}",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green[800],
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                      Container(
                        margin: const EdgeInsets.only(top: 4, bottom: 20),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.indigo[50],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              "Total Labor Cost:",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.indigo[900],
                              ),
                            ),
                            Text(
                              "₹${totalLaborCost.toStringAsFixed(0)}",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.indigo[900],
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),

              const Divider(thickness: 1, height: 40),

              FutureBuilder<List<Map<String, dynamic>>>(
                future: DatabaseHelper.instance.database.then(
                  (db) => db.rawQuery(
                    '''
                    SELECT j.advance_paid, j.scrap_value, j.discount,
                           (SELECT SUM(amount) FROM payments WHERE job_id = j.id) as total_payments
                    FROM jobs j
                    WHERE j.id = ?
                  ''',
                    [currentJob['id']],
                  ),
                ),
                builder: (context, snapshot) {
                  double rawAdvance = 0;
                  double totalReceived = 0;
                  double scrapAmt = 0;
                  double discountAmt = 0;

                  if (snapshot.hasData && snapshot.data!.isNotEmpty) {
                    var freshJob = snapshot.data!.first;
                    rawAdvance =
                        (freshJob['advance_paid'] as num?)?.toDouble() ?? 0.0;
                    double paymentsSum =
                        (freshJob['total_payments'] as num?)?.toDouble() ?? 0.0;
                    totalReceived = rawAdvance + paymentsSum;
                    scrapAmt =
                        (freshJob['scrap_value'] as num?)?.toDouble() ?? 0.0;
                    discountAmt =
                        (freshJob['discount'] as num?)?.toDouble() ?? 0.0;
                  } else {
                    rawAdvance =
                        (currentJob['advance_paid'] as num?)?.toDouble() ?? 0.0;
                    double paymentsSum =
                        (currentJob['paid_sum'] as num?)?.toDouble() ?? 0.0;
                    totalReceived = rawAdvance + paymentsSum;
                    scrapAmt =
                        (currentJob['scrap_value'] as num?)?.toDouble() ?? 0.0;
                    discountAmt =
                        (currentJob['discount'] as num?)?.toDouble() ?? 0.0;
                  }

                  double finalBalance =
                      total - (totalReceived + scrapAmt + discountAmt);

                  return _buildInfoCard(
                    title: "Payment Summary",
                    content: Column(
                      children: [
                        _buildPaymentRow(
                          "Sub Total / Gross",
                          total,
                          isBold: true,
                        ),
                        const Divider(),
                        _buildPaymentRow(
                          "Total Received",
                          totalReceived,
                          color: Colors.blue[700],
                          onEdit: () =>
                              _editJobAmount("Advance", rawAdvance, true),
                        ),
                        _buildPaymentRow(
                          "Scrap Deducted",
                          scrapAmt,
                          color: Colors.orange[800],
                          onEdit: () =>
                              _editJobAmount("Scrap", scrapAmt, false),
                        ),
                        if (discountAmt > 0)
                          _buildPaymentRow(
                            "Discount Given",
                            discountAmt,
                            color: Colors.purple[700],
                          ),
                        const Divider(),
                        _buildPaymentRow(
                          finalBalance > 0 ? "BALANCE DUE" : (finalBalance < 0 ? "CREDIT" : "FULLY SETTLED"),
                          finalBalance.abs(),
                          color: finalBalance > 0 ? Colors.red : (finalBalance < 0 ? Colors.blue : Colors.green),
                          isBold: true,
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    _printOrShareBill(context);
                  },
                  icon: const Icon(Icons.print_rounded),
                  label: const Text("Print / Share Bill"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4F46E5),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    ),
  ),
);
  }

  List<Widget> _buildLinkedProductionView(
    List<dynamic> inList,
    List<dynamic> outList,
  ) {
    List<Widget> views = [];
    Map<String, dynamic> inputMap = {};
    for (var item in inList) {
      if (item['id'] != null) {
        inputMap[item['id'].toString()] = item;
      }
    }

    Set<String> usedInputIds = {};

    if (outList.isNotEmpty) {
      views.add(_buildSectionBadge("Output Products", Colors.blue));
      for (var prod in outList) {
        List<dynamic> links = prod['linked_materials'] ?? [];
        if (links.isEmpty && prod['linked_ids'] != null) {
          links = (prod['linked_ids'] as List)
              .map((id) => {'id': id, 'used_qty': 1})
              .toList();
        }

        List<dynamic> usedMaterials = [];
        for (var link in links) {
          String linkId = link['id'];
          if (inputMap.containsKey(linkId)) {
            var matDetail = Map<String, dynamic>.from(inputMap[linkId]);
            matDetail['used_qty'] = link['used_qty'] ?? 1;
            usedMaterials.add(matDetail);
            usedInputIds.add(linkId);
          }
        }

        if (usedMaterials.isEmpty) {
          usedMaterials = inList
              .where((m) => m['linked_to'] == prod['name'])
              .map((m) => {...m, 'used_qty': m['qty']})
              .toList();
          for (var m in usedMaterials) {
            if (m['id'] != null) usedInputIds.add(m['id']);
          }
        }

        views.add(_buildProductItem(prod, usedMaterials));
      }
    }

    List<dynamic> orphans = inList
        .where(
          (item) =>
              item['id'] != null &&
              !usedInputIds.contains(item['id'].toString()),
        )
        .toList();

    if (orphans.isNotEmpty || (outList.isEmpty && inList.isNotEmpty)) {
      views.add(const SizedBox(height: 20));
      views.add(_buildSectionBadge("Unlinked Materials", Colors.orange));
      List<dynamic> displayList = usedInputIds.isEmpty && outList.isEmpty
          ? inList
          : orphans;

      for (var mat in displayList) {
        views.add(_buildSimpleItem(mat));
      }
    }

    return views;
  }

  Widget _buildProductItem(dynamic product, List<dynamic> materials) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withOpacity(0.05),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    const Icon(Icons.inventory_2, color: Colors.blue, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        product['name'],
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Color(0xFF1A237E),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  "Qty: ${product['qty']}",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          if (materials.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Divider(height: 1),
            ),
            const Text(
              "Made using:",
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
            const SizedBox(height: 4),
            ...materials.map(
              (mat) => Padding(
                padding: const EdgeInsets.only(left: 10, bottom: 4),
                child: Row(
                  children: [
                    const Icon(
                      Icons.subdirectory_arrow_right,
                      size: 16,
                      color: Colors.grey,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      mat['name'],
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      "Uses x${mat['used_qty']} (from ${mat['qty']})",
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[700],
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSimpleItem(dynamic item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.orange[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.withOpacity(0.1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const Icon(Icons.layers, size: 16, color: Colors.orange),
              const SizedBox(width: 8),
              Text(
                item['name'],
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          Text(
            "x${item['qty']}",
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.orange[900],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard({required String title, required Widget content}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.grey[500],
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 10),
          content,
        ],
      ),
    );
  }

  Widget _buildSectionBadge(String title, Color color) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(top: 8, bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          title,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentRow(
    String label,
    num amount, {
    bool isBold = false,
    Color? color,
    VoidCallback? onEdit,
  }) {
    final fmt = NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 0,
    ).format(amount);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              if (onEdit != null)
                InkWell(
                  onTap: onEdit,
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8.0),
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
              Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
          Text(
            fmt,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: color ?? Colors.black,
            ),
          ),
        ],
      ),
    );
  }
}
