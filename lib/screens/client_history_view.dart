import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../database_helper.dart';
import '../widgets/payment_dialog.dart';
import '../providers.dart';

// --- HELPER DECORATION ---
BoxDecoration _cardDecoration() {
  return BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(16),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(0.04),
        blurRadius: 10,
        offset: const Offset(0, 4),
      ),
    ],
  );
}

// --- WIDGET ---
class ClientHistoryView extends ConsumerStatefulWidget {
  const ClientHistoryView({super.key});

  @override
  ConsumerState<ClientHistoryView> createState() => _ClientHistoryViewState();
}

class _ClientHistoryViewState extends ConsumerState<ClientHistoryView> {
  final _searchCtrl = TextEditingController();
  String _query = "";
  Timer? _debounce;

  // Smart Search State
  final LayerLink _layerLink = LayerLink();
  List<Map<String, dynamic>> _suggestions = [];
  bool _showSuggestions = false;

  // Smart Sorting States
  String _searchSortFilter = 'Date'; // Used when searching
  String _insightsSortFilter = 'Due'; // Used when viewing main list

  final Color _primaryColor = const Color(0xFF1A237E);

  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearch(String q) {
    final cleanQ = q.trim();
    if (cleanQ.isEmpty) {
      setState(() {
        _query = cleanQ;
        _showSuggestions = false;
        _suggestions.clear();
      });
      return;
    }

    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      // 🔥 FORCE FRESH FETCH EVERY TIME YOU TYPE
      ref.invalidate(clientHistoryProvider(cleanQ));

      setState(() => _query = cleanQ);
      if (!mounted) return;
      final results = await DatabaseHelper.instance.searchClients(cleanQ);
      if (mounted) {
        setState(() {
          _suggestions = List<Map<String, dynamic>>.from(results);
          _showSuggestions = _suggestions.isNotEmpty;
        });
      }
    });
  }

  void _selectSuggestion(String? clientName) {
    if (clientName == null || clientName.trim().isEmpty) return;

    final cleanName = clientName.trim();
    _searchCtrl.text = cleanName;
    _searchCtrl.selection = TextSelection.fromPosition(
      TextPosition(offset: cleanName.length),
    );

    // 🔥 DESTROY CACHE ON CLICK SO IT LOADS FRESH
    ref.invalidate(clientHistoryProvider(cleanName));

    setState(() {
      _query = cleanName;
      _showSuggestions = false;
    });
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final bool isSearching = _searchCtrl.text.isNotEmpty;

    // LIVE-WIRE CACHE INVALIDATION
    ref.listen(dbRefreshTriggerProvider, (previous, next) {
      if (_query.isNotEmpty) {
        ref.invalidate(clientHistoryProvider(_query));
      }
      ref.invalidate(activeJobsProvider);
    });

    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        setState(() => _showSuggestions = false);
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        body: Stack(
          children: [
            Column(
              children: [
                _buildHeader(isSearching),
                Expanded(
                  child: isSearching
                      ? _buildSearchResults()
                      : _buildTopDebtorsList(),
                ),
              ],
            ),
            if (_showSuggestions && _suggestions.isNotEmpty)
              Positioned(
                child: CompositedTransformFollower(
                  link: _layerLink,
                  showWhenUnlinked: false,
                  targetAnchor: Alignment.bottomLeft,
                  followerAnchor: Alignment.topLeft,
                  offset: const Offset(0, 8),
                  child: SizedBox(
                    width: MediaQuery.of(context).size.width - 40,
                    child: _buildSuggestionsList(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool isSearching) {
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isSearching ? "Search Results" : "Client Insights",
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      isSearching
                          ? "Showing matches for '${_searchCtrl.text}'"
                          : (_insightsSortFilter == 'Orders'
                                ? "Top Clients by Total Orders"
                                : (_insightsSortFilter == 'AZ'
                                    ? "Clients Alphabetical (A-Z)"
                                    : (_insightsSortFilter == 'Date'
                                        ? "Clients by Newest Order"
                                        : "Top Outstanding Dues"))),
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withOpacity(0.8),
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.sort_rounded, color: Colors.white),
                tooltip: "Sort Options",
                onSelected: (val) {
                  setState(() {
                    if (isSearching) {
                      _searchSortFilter = val;
                    } else {
                      _insightsSortFilter = val;
                    }
                  });
                },
                itemBuilder: (context) {
                  if (isSearching) {
                    return [
                      PopupMenuItem(
                        value: 'Date',
                        child: Text(
                          "📅 By Date (Newest)",
                          style: TextStyle(
                            fontWeight: _searchSortFilter == 'Date'
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: _searchSortFilter == 'Date'
                                ? _primaryColor
                                : Colors.black87,
                          ),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'Value',
                        child: Text(
                          "💰 By Value (Highest)",
                          style: TextStyle(
                            fontWeight: _searchSortFilter == 'Value'
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: _searchSortFilter == 'Value'
                                ? _primaryColor
                                : Colors.black87,
                          ),
                        ),
                      ),
                    ];
                  } else {
                    return [
                      PopupMenuItem(
                        value: 'Due',
                        child: Text(
                          "⚠️ Highest Due",
                          style: TextStyle(
                            fontWeight: _insightsSortFilter == 'Due'
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: _insightsSortFilter == 'Due'
                                ? _primaryColor
                                : Colors.black87,
                          ),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'Orders',
                        child: Text(
                          "📦 Most Orders",
                          style: TextStyle(
                            fontWeight: _insightsSortFilter == 'Orders'
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: _insightsSortFilter == 'Orders'
                                ? _primaryColor
                                : Colors.black87,
                          ),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'AZ',
                        child: Text(
                          "🔤 Alphabetical (A-Z)",
                          style: TextStyle(
                            fontWeight: _insightsSortFilter == 'AZ'
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: _insightsSortFilter == 'AZ'
                                ? _primaryColor
                                : Colors.black87,
                          ),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'Date',
                        child: Text(
                          "📅 By Date (Newest)",
                          style: TextStyle(
                            fontWeight: _insightsSortFilter == 'Date'
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: _insightsSortFilter == 'Date'
                                ? _primaryColor
                                : Colors.black87,
                          ),
                        ),
                      ),
                    ];
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 20),
          CompositedTransformTarget(
            link: _layerLink,
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearch,
              onTap: () {
                if (_suggestions.isNotEmpty && _searchCtrl.text.isNotEmpty) {
                  setState(() => _showSuggestions = true);
                }
              },
              style: const TextStyle(color: Colors.black87),
              decoration: InputDecoration(
                hintText: "Search Client Name or Phone...",
                hintStyle: TextStyle(color: Colors.grey[500], fontSize: 14),
                prefixIcon: Icon(
                  Icons.person_search_rounded,
                  color: _primaryColor,
                ),
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
                suffixIcon: isSearching
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        color: Colors.grey,
                        onPressed: () {
                          _searchCtrl.clear();
                          _onSearch("");
                        },
                      )
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestionsList() {
    return Material(
      elevation: 8,
      shadowColor: Colors.black.withOpacity(0.2),
      borderRadius: BorderRadius.circular(16),
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      child: Container(
        constraints: const BoxConstraints(maxHeight: 280),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          shrinkWrap: true,
          itemCount: _suggestions.length,
          separatorBuilder: (ctx, i) =>
              Divider(height: 1, color: Colors.grey[100]),
          itemBuilder: (ctx, i) {
            final s = _suggestions[i];
            final name = s['client_name']?.toString() ?? 'Unknown';
            final phone = s['client_phone']?.toString() ?? '';
            final place = s['client_place']?.toString() ?? '';

            final List<String> details = [];
            if (phone.isNotEmpty) details.add(phone);
            if (place.isNotEmpty) details.add(place);

            return ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 2,
              ),
              leading: CircleAvatar(
                backgroundColor: _primaryColor.withOpacity(0.1),
                radius: 18,
                child: Icon(Icons.person, color: _primaryColor, size: 20),
              ),
              title: Text(
                name,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              subtitle: details.isNotEmpty
                  ? Text(
                      details.join(' • '),
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    )
                  : null,
              onTap: () => _selectSuggestion(name),
            );
          },
        ),
      ),
    );
  }

  Widget _buildTopDebtorsList() {
    final jobsAsync = ref.watch(activeJobsProvider);

    return jobsAsync.when(
      data: (rawJobs) {
        if (rawJobs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.check_circle_outline,
                  size: 80,
                  color: Colors.green[200],
                ),
                const SizedBox(height: 15),
                Text(
                  "All clean!\nNo pending jobs or dues.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[500],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          );
        }

        Map<String, Map<String, dynamic>> mergedMap = {};

        for (var job in rawJobs) {
          String rawName = job['client_name']?.toString() ?? "Unknown";
          String key = rawName.trim().toLowerCase();

          double jCost = (job['total_cost'] as num?)?.toDouble() ?? 0.0;
          double jPaid = (job['paid_sum'] as num?)?.toDouble() ?? 0.0;
          double jDisc = (job['discount'] as num?)?.toDouble() ?? 0.0;
          double jScrap = (job['scrap_value'] as num?)?.toDouble() ?? 0.0;

          double jobDue = jCost - jPaid - jDisc - jScrap;

          Map<String, dynamic> summary = {
            'bill_no': job['bill_no']?.toString() ?? '',
            'status': job['status']?.toString() ?? 'Ongoing',
            'created_at':
                job['created_at']?.toString() ??
                DateTime.now().toIso8601String(),
            'total_cost': jCost,
          };

          if (mergedMap.containsKey(key)) {
            int currentCount =
                (mergedMap[key]!['job_count'] as num?)?.toInt() ?? 0;
            double currentDue =
                (mergedMap[key]!['total_due'] as num?)?.toDouble() ?? 0.0;
            double currentTotalCost =
                (mergedMap[key]!['total_cost'] as num?)?.toDouble() ?? 0.0;

            mergedMap[key]!['job_count'] = currentCount + 1;
            mergedMap[key]!['total_due'] = currentDue + jobDue;
            mergedMap[key]!['total_cost'] = currentTotalCost + jCost;

            List summaries = mergedMap[key]!['job_summaries'] ?? [];
            summaries.add(summary);
            mergedMap[key]!['job_summaries'] = summaries;

            if ((mergedMap[key]!['client_phone'] == null ||
                    mergedMap[key]!['client_phone'].toString().isEmpty) &&
                (job['client_phone'] != null &&
                    job['client_phone'].toString().isNotEmpty)) {
              mergedMap[key]!['client_phone'] = job['client_phone'];
              mergedMap[key]!['client_name'] = job['client_name'];
            }
          } else {
            mergedMap[key] = {
              'client_name': job['client_name'] ?? 'Unknown',
              'client_phone': job['client_phone'],
              'job_count': 1,
              'total_due': jobDue,
              'total_cost': jCost,
              'job_summaries': [summary],
            };
          }
        }

        List<Map<String, dynamic>> debtors = mergedMap.values.toList();

        if (_insightsSortFilter == 'Orders') {
          debtors.sort((a, b) {
            int countA = (a['job_count'] as num?)?.toInt() ?? 0;
            int countB = (b['job_count'] as num?)?.toInt() ?? 0;
            return countB.compareTo(countA);
          });
        } else if (_insightsSortFilter == 'AZ') {
          debtors.sort((a, b) {
            String nameA = (a['client_name'] as String? ?? '').toLowerCase();
            String nameB = (b['client_name'] as String? ?? '').toLowerCase();
            return nameA.compareTo(nameB);
          });
        } else if (_insightsSortFilter == 'Date') {
          debtors.sort((a, b) {
            List summariesA = a['job_summaries'] ?? [];
            List summariesB = b['job_summaries'] ?? [];
            DateTime dateA = summariesA.isEmpty
                ? DateTime(2000)
                : summariesA
                    .map((j) => DateTime.tryParse(j['created_at'] ?? '') ?? DateTime(2000))
                    .reduce((val, elem) => val.isAfter(elem) ? val : elem);
            DateTime dateB = summariesB.isEmpty
                ? DateTime(2000)
                : summariesB
                    .map((j) => DateTime.tryParse(j['created_at'] ?? '') ?? DateTime(2000))
                    .reduce((val, elem) => val.isAfter(elem) ? val : elem);
            return dateB.compareTo(dateA); // Newest first
          });
        } else {
          debtors.sort((a, b) {
            double dueA = (a['total_due'] as num?)?.toDouble() ?? 0.0;
            double dueB = (b['total_due'] as num?)?.toDouble() ?? 0.0;
            return dueB.compareTo(dueA);
          });
        }

        return RefreshIndicator(
          onRefresh: () async => ref.refresh(activeJobsProvider),
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
            itemCount: debtors.length,
            itemBuilder: (ctx, index) {
              final client = debtors[index];
              double due = (client['total_due'] as num?)?.toDouble() ?? 0.0;
              double totalCost =
                  (client['total_cost'] as num?)?.toDouble() ?? 0.0;

              List allSummaries = client['job_summaries'] ?? [];

              // 🔥 Filter to ONLY show active high-priority jobs in the 3 slots
              List activeSummaries = allSummaries.where((job) {
                final status = (job['status'] ?? 'Ongoing')
                    .toString()
                    .toLowerCase();
                return status != 'ready' &&
                    status != 'done' &&
                    status != 'delivered';
              }).toList();

              // 🔥 Sort the active ones by Priority, then by Date
              activeSummaries.sort((a, b) {
                int getPriority(Map j) {
                  final status = (j['status'] ?? 'Ongoing')
                      .toString()
                      .toLowerCase();
                  if (status == 'nothing') return 0; // Highest priority
                  if (status == 'ongoing') return 1; // Second priority
                  return 2; // Catch-all
                }

                int pA = getPriority(a);
                int pB = getPriority(b);

                if (pA != pB) return pA.compareTo(pB);

                DateTime dateA =
                    DateTime.tryParse(a['created_at'] ?? '') ?? DateTime.now();
                DateTime dateB =
                    DateTime.tryParse(b['created_at'] ?? '') ?? DateTime.now();
                return dateB.compareTo(dateA);
              });

              // Take top 3 for the UI
              List displayedJobs = activeSummaries.take(3).toList();

              // Calculate exactly how many jobs are NOT being shown
              int hiddenJobsCount = allSummaries.length - displayedJobs.length;

              Color rankColor;
              if (index == 0)
                rankColor = const Color(0xFFFFD700);
              else if (index == 1)
                rankColor = const Color(0xFFC0C0C0);
              else if (index == 2)
                rankColor = const Color(0xFFCD7F32);
              else
                rankColor = Colors.grey[200]!;

              Color rankText = index < 3 ? Colors.white : Colors.grey[700]!;

              String rightTopLabel = "DUE";
              String rightBottomLabel;
              Color rightColor;

              if (totalCost == 0) {
                rightTopLabel = "STATUS";
                rightBottomLabel = "ESTIMATE";
                rightColor = Colors.orange[800]!;
              } else if (due < 0) {
                rightTopLabel = "STATUS";
                rightBottomLabel = "CREDIT ₹${due.abs().toStringAsFixed(0)}";
                rightColor = Colors.blue[700]!;
              } else if (due == 0) {
                rightTopLabel = "STATUS";
                rightBottomLabel = "CLEAR";
                rightColor = Colors.green[700]!;
              } else {
                rightBottomLabel = "₹${due.toStringAsFixed(0)}";
                rightColor = const Color(0xFFC62828); // Deep Red
              }

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: _cardDecoration(),
                clipBehavior: Clip.antiAlias,
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => _selectSuggestion(client['client_name']),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            margin: const EdgeInsets.only(top: 4),
                            decoration: BoxDecoration(
                              color: rankColor,
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                "#${index + 1}",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: rankText,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),

                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  client['client_name'] ?? "Unknown",
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: Color(0xFF2d3436),
                                  ),
                                ),
                                const SizedBox(height: 8),

                                if (displayedJobs.isNotEmpty)
                                  ...displayedJobs.map((job) {
                                    final double cost =
                                        (job['total_cost'] as num?)
                                            ?.toDouble() ??
                                        0.0;
                                    final String status =
                                        job['status'] ?? 'Ongoing';
                                    final date =
                                        DateTime.tryParse(
                                          job['created_at'] ?? '',
                                        ) ??
                                        DateTime.now();

                                    String displayStatus = status.toUpperCase();
                                    Color sBg = Colors.grey[200]!;
                                    Color sText = Colors.grey[800]!;

                                    if (cost == 0) {
                                      displayStatus = "ESTIMATE";
                                      sBg = Colors.orange[50]!;
                                      sText = Colors.orange[800]!;
                                    } else if (status == 'Nothing') {
                                      sBg = Colors.grey[200]!;
                                      sText = Colors.grey[700]!;
                                    } else if (status == 'Ongoing') {
                                      sBg = Colors.orange[50]!;
                                      sText = Colors.orange[800]!;
                                    }

                                    String bNo =
                                        job['bill_no']?.toString() ?? '';
                                    String billText =
                                        bNo.isNotEmpty && bNo != 'null'
                                        ? "Bill #$bNo"
                                        : "Job";

                                    return Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 6.0,
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: sBg,
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              border: Border.all(
                                                color: sText.withOpacity(0.3),
                                              ),
                                            ),
                                            child: Text(
                                              displayStatus,
                                              style: const TextStyle(
                                                fontSize: 8,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.black,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            "$billText • ${DateFormat('dd MMM yy').format(date)}",
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey[600],
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),

                                // 🔥 DYNAMICALLY SHOW THE HIDDEN JOB COUNT 🔥
                                if (hiddenJobsCount > 0)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2.0),
                                    child: Text(
                                      "+ $hiddenJobsCount more jobs...",
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey[500],
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),

                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                rightTopLabel,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: rightTopLabel == 'DUE'
                                      ? Colors.red[300]
                                      : Colors.grey[500],
                                  letterSpacing: 1,
                                ),
                              ),
                              Text(
                                rightBottomLabel,
                                style: TextStyle(
                                  fontSize: rightTopLabel == 'DUE' ? 18 : 14,
                                  fontWeight: FontWeight.w900,
                                  color: rightColor,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(width: 10),
                          Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 14,
                              color: Colors.grey[400],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text("Error: $err")),
    );
  }

  Widget _buildSearchResults() {
    final historyAsync = ref.watch(clientHistoryProvider(_query));

    return historyAsync.when(
      data: (jobs) {
        if (jobs.isEmpty)
          return const Center(
            child: Text(
              "No records found.",
              style: TextStyle(color: Colors.grey),
            ),
          );

        List<Map<String, dynamic>> sortedJobs = List.from(jobs);

        if (_searchSortFilter == 'Date') {
          sortedJobs.sort((a, b) {
            DateTime dateA =
                DateTime.tryParse(a['created_at'] ?? '') ?? DateTime.now();
            DateTime dateB =
                DateTime.tryParse(b['created_at'] ?? '') ?? DateTime.now();
            return dateB.compareTo(dateA);
          });
        } else if (_searchSortFilter == 'Value') {
          sortedJobs.sort((a, b) {
            double costA = (a['total_cost'] as num?)?.toDouble() ?? 0.0;
            double costB = (b['total_cost'] as num?)?.toDouble() ?? 0.0;
            return costB.compareTo(costA);
          });
        }

        // SAFE TOTAL CALCULATION
        double totalDue = 0;
        for (var j in sortedJobs) {
          double c = (j['total_cost'] as num?)?.toDouble() ?? 0.0;
          double p = (j['paid_sum'] as num?)?.toDouble() ?? 0.0;
          double d = (j['discount'] as num?)?.toDouble() ?? 0.0;
          double s = (j['scrap_value'] as num?)?.toDouble() ?? 0.0;

          double bal = c - p - d - s;
          if (bal > 0) totalDue += bal;
        }

        return Column(
          children: [
            Container(
              margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1A237E), Color(0xFF5C6BC0)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF1A237E).withOpacity(0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Text(
                    sortedJobs.first['client_name'].toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 15),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _HeaderStat("Total Jobs", "${sortedJobs.length}"),
                      Container(
                        width: 1,
                        height: 30,
                        color: Colors.white24,
                        margin: const EdgeInsets.symmetric(horizontal: 30),
                      ),
                      _HeaderStat(
                        "Total Due",
                        "₹${totalDue.toStringAsFixed(0)}",
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(clientHistoryProvider(_query));
                },
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                  itemCount: sortedJobs.length,
                  itemBuilder: (ctx, i) =>
                      _DetailedJobCard(job: sortedJobs[i], query: _query),
                ),
              ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, s) => Center(child: Text("Error: $e")),
    );
  }

  Widget _HeaderStat(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.8)),
        ),
      ],
    );
  }
}

// =========================================================================
// STATEFUL DETAILED JOB CARD
// =========================================================================

class _DetailedJobCard extends ConsumerStatefulWidget {
  final Map<String, dynamic> job;
  final String query;

  const _DetailedJobCard({required this.job, required this.query});

  @override
  ConsumerState<_DetailedJobCard> createState() => _DetailedJobCardState();
}

class _DetailedJobCardState extends ConsumerState<_DetailedJobCard> {
  List<Map<String, dynamic>> _payments = [];
  bool _isLoadingPayments = true;

  @override
  void initState() {
    super.initState();
    _fetchPayments();
  }

  Future<void> _fetchPayments() async {
    final payments = await DatabaseHelper.instance.getJobPayments(
      widget.job['id'],
    );
    if (mounted) {
      setState(() {
        _payments = payments;
        _isLoadingPayments = false;
      });
    }
  }

  Future<void> _deleteJob() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        clipBehavior: Clip.antiAlias,
        titlePadding: EdgeInsets.zero,
        contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        title: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: Colors.red,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Row(
            children: const [
              Icon(Icons.warning_rounded, color: Colors.white, size: 28),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  "Delete Job?",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
        content: const Text(
          "This action cannot be undone. Are you sure you want to permanently delete this job?",
          style: TextStyle(fontSize: 16, height: 1.4),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(foregroundColor: Colors.grey[700]),
            child: const Text("Cancel", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              elevation: 0,
            ),
            child: const Text("Delete", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      if (!mounted) return;
      await DatabaseHelper.instance.deleteJob(widget.job['id']);
      ref.read(dbRefreshTriggerProvider.notifier).state++;
    }
  }

  @override
  Widget build(BuildContext context) {
    final date = DateTime.parse(
      widget.job['created_at'] ?? DateTime.now().toIso8601String(),
    );
    final String status = widget.job['status'] ?? 'Ongoing';

    // NULL-SAFE MATH WITH DISCOUNT & SCRAP
    final double cost = (widget.job['total_cost'] as num?)?.toDouble() ?? 0.0;
    final double paid = (widget.job['paid_sum'] as num?)?.toDouble() ?? 0.0;
    final double discount = (widget.job['discount'] as num?)?.toDouble() ?? 0.0;
    final double scrap = (widget.job['scrap_value'] as num?)?.toDouble() ?? 0.0;

    final double bal = cost - paid - discount - scrap;
    final double amountToPay = bal > 0 ? bal : 0;

    // STRICT BALANCE TEXT LOGIC
    String balText;
    Color balColor;

    if (cost == 0) {
      balText = "ESTIMATE";
      balColor = Colors.orange[800]!;
    } else if (amountToPay == 0) {
      balText = "₹0";
      balColor = Colors.green[700]!;
    } else {
      balText = "₹${amountToPay.toStringAsFixed(0)}";
      balColor = Colors.red[800]!;
    }

    Map<String, dynamic> itemsData = {};
    try {
      final decoded = jsonDecode(widget.job['items'] ?? "{}");
      if (decoded is Map<String, dynamic>) {
        itemsData = decoded;
      }
    } catch (_) {}

    final List<dynamic> inList = itemsData['in'] ?? [];
    final List<dynamic> outList = itemsData['out'] ?? [];

    List<dynamic> materials = List.from(inList);
    List<dynamic> products = List.from(outList);

    if (materials.isEmpty &&
        widget.job['material_brought'] != null &&
        widget.job['material_brought'].toString().isNotEmpty) {
      materials.add({
        'name': widget.job['material_brought'],
        'qty': widget.job['qty_given'],
      });
    }
    if (products.isEmpty &&
        widget.job['product_type'] != null &&
        widget.job['product_type'].toString().isNotEmpty) {
      products.add({
        'name': widget.job['product_type'],
        'qty': widget.job['target_qty'],
      });
    }

    List<String> remainingMats = [];
    for (var mat in materials) {
      String matId = mat['id']?.toString() ?? '';
      String name = mat['name']?.toString() ?? 'Unknown';
      int totalQty = (mat['qty'] as num?)?.toInt() ?? 0;

      int used = 0;
      for (var prod in products) {
        for (var link in (prod['linked_materials'] ?? [])) {
          if (link['id'] == matId) {
            used += (link['used_qty'] as num?)?.toInt() ?? 0;
          }
        }
      }

      int rem = totalQty - used;
      if (rem > 0) {
        remainingMats.add("$name: $rem");
      }
    }
    String remainingText = remainingMats.isEmpty
        ? "All Materials Used"
        : "Rem: ${remainingMats.join(', ')}";

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: _cardDecoration(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
              border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today_rounded,
                      size: 14,
                      color: Colors.grey[500],
                    ),
                    const SizedBox(width: 6),
                    Text(
                      DateFormat('dd MMM yyyy').format(date),
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: Colors.grey[700],
                      ),
                    ),
                  ],
                ),
                if (widget.job['bill_no'] != null &&
                    widget.job['bill_no'].toString().isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      "#${widget.job['bill_no']}",
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[700],
                      ),
                    ),
                  ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "MATERIAL IN",
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.orange,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 6),
                          if (inList.isEmpty)
                            Text(
                              widget.job['material_brought'] ?? "-",
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            )
                          else
                            ...inList.map(
                              (item) => Padding(
                                padding: const EdgeInsets.only(bottom: 2),
                                child: Text(
                                  "• ${item['name']}",
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 40,
                      color: Colors.grey[200],
                      margin: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text(
                            "WORK DONE",
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.blue,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 6),
                          if (outList.isEmpty)
                            Text(
                              widget.job['product_type'] ?? "-",
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                              textAlign: TextAlign.right,
                            )
                          else
                            ...outList.map(
                              (item) => Padding(
                                padding: const EdgeInsets.only(bottom: 2),
                                child: Text(
                                  "${item['name']} •",
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  textAlign: TextAlign.right,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: remainingMats.isEmpty
                        ? Colors.green.withOpacity(0.4)
                        : Colors.orange.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        remainingMats.isEmpty
                            ? Icons.check_circle_outline
                            : Icons.inventory_2_outlined,
                        size: 14,
                        color: Colors.black,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          remainingText,
                          style: const TextStyle(
                            fontSize: 11,
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

                if (!_isLoadingPayments && _payments.isNotEmpty) ...[
                  const Divider(height: 24),
                  Row(
                    children: [
                      Icon(Icons.history, size: 14, color: Colors.green[700]),
                      const SizedBox(width: 4),
                      Text(
                        "PAYMENT HISTORY",
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.green[700],
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  ..._payments.map((p) {
                    final pDate =
                        DateTime.tryParse(p['payment_date'] ?? '') ??
                        DateTime.now();
                    final double pAmt = (p['amount'] as num?)?.toDouble() ?? 0;

                    String note = (p['notes'] ?? p['note'] ?? '')
                        .toString()
                        .trim();
                    if (note.isEmpty) note = "Payment";

                    Color amtColor = Colors.green[800]!;
                    if (note.toLowerCase().contains('discount')) {
                      amtColor = Colors.purple[700]!;
                    } else if (note.toLowerCase().contains('scrap')) {
                      amtColor = Colors.orange[800]!;
                    }

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  note,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey[800],
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  DateFormat('dd MMM yyyy').format(pDate),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey[500],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            "- ₹${pAmt.toStringAsFixed(0)}",
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              color: amtColor,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ],

                const Divider(height: 24),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        _StatusBadge(status),
                        const SizedBox(width: 8),
                        InkWell(
                          onTap: _deleteJob,
                          borderRadius: BorderRadius.circular(20),
                          child: Padding(
                            padding: const EdgeInsets.all(4.0),
                            child: Icon(
                              Icons.delete_outline,
                              size: 20,
                              color: Colors.red[400],
                            ),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        _StatCol("Total", "₹${cost.toStringAsFixed(0)}"),
                        Container(
                          width: 1,
                          height: 20,
                          color: Colors.grey[300],
                          margin: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                        _StatCol("Balance", balText, color: balColor),

                        if (amountToPay > 0) ...[
                          const SizedBox(width: 12),
                          ElevatedButton(
                            onPressed: () async {
                              await showDialog(
                                context: context,
                                builder: (c) =>
                                    PaymentDialog(job: widget.job, ref: ref),
                              );
                              _fetchPayments();
                              ref
                                  .read(dbRefreshTriggerProvider.notifier)
                                  .state++;
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green[700],
                              foregroundColor: Colors.white,
                              minimumSize: const Size(0, 32),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              elevation: 0,
                            ),
                            child: const Text(
                              "PAY",
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _StatCol(String label, String value, {Color? color}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Colors.grey[500],
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: color ?? Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _StatusBadge(String status) {
    Color bg;
    Color text;
    String label = status.toUpperCase();

    if (status == 'Nothing') {
      bg = Colors.grey[200]!;
      text = Colors.black;
    } else if (status == 'Ongoing') {
      bg = Colors.orange[50]!;
      text = Colors.orange[800]!;
    } else if (status == 'Ready') {
      bg = Colors.blue[50]!;
      text = Colors.blue[700]!;
    } else {
      bg = Colors.green[50]!;
      text = Colors.green[700]!;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: text.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: Colors.black,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
