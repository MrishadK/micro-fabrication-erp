import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import '../database_helper.dart';
import '../providers.dart';
import 'scrollable_autocomplete_options.dart';

/// Compact Popup Dialog for creating a New Job Order.
/// Designed specifically as a compact, modern workstation modal dialog
/// with high-density layout and side-by-side materials/products sections.
class ReceiptForm extends ConsumerStatefulWidget {
  final bool isDialog;
  const ReceiptForm({super.key, this.isDialog = true});

  /// Static helper to display the compact popup dialog from anywhere
  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const ReceiptForm(isDialog: true),
    );
  }

  @override
  ConsumerState<ReceiptForm> createState() => _ReceiptFormState();
}

class _ReceiptFormState extends ConsumerState<ReceiptForm> {
  final _formKey = GlobalKey<FormState>();
  final _billNoCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _placeCtrl = TextEditingController();
  final _costCtrl = TextEditingController();
  final _advanceCtrl = TextEditingController();
  final _detailsCtrl = TextEditingController();
  final ScrollController _formScrollCtrl = ScrollController();

  final List<Map<String, dynamic>> _materials = [];
  final List<Map<String, dynamic>> _products = [];

  List<String> _knownItems = [];
  Map<String, double> _historicalRates = {};

  DateTime _deadlineDate = DateTime.now().add(const Duration(days: 7));
  DateTime _billDate = DateTime.now();

  static const Color _primary = Color(0xFF1A237E);
  static const Color _accent = Color(0xFFFF6D00);

  @override
  void initState() {
    super.initState();
    _loadSuggestions();
    _loadNextBillNumber();
    _addMaterial();
    _addProduct();
  }

  @override
  void dispose() {
    _billNoCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _placeCtrl.dispose();
    _costCtrl.dispose();
    _advanceCtrl.dispose();
    _detailsCtrl.dispose();
    _formScrollCtrl.dispose();
    super.dispose();
  }

  // --- FETCH HISTORICAL DATA ---
  Future<void> _loadSuggestions() async {
    final items = await DatabaseHelper.instance.getAllItemNames();

    Map<String, double> rates = {};
    try {
      final active = await DatabaseHelper.instance.getActiveJobs();
      final history = await DatabaseHelper.instance.getHistoryJobs("");
      final allJobs = [...active, ...history];

      allJobs.sort((a, b) => (b['id'] as int).compareTo(a['id'] as int));

      for (var job in allJobs) {
        if (job['items'] != null && job['items'].toString().startsWith('{')) {
          final data = jsonDecode(job['items']);
          for (var prod in data['out'] ?? []) {
            String pName = prod['name']?.toString() ?? '';
            double pRate = (prod['rate'] as num?)?.toDouble() ?? 0.0;

            if (pName.isNotEmpty && pRate > 0 && !rates.containsKey(pName)) {
              rates[pName] = pRate;
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Could not parse historical rates: $e");
    }

    if (mounted) {
      setState(() {
        _knownItems = items;
        _historicalRates = rates;
      });
    }
  }

  Future<void> _loadNextBillNumber() async {
    String nextBill = await DatabaseHelper.instance.generateNextBillNumber();
    if (mounted && _billNoCtrl.text.isEmpty) {
      setState(() => _billNoCtrl.text = nextBill);
    }
  }

  String _generateId(String prefix) =>
      "${prefix}_${DateTime.now().microsecondsSinceEpoch}";

  void _addMaterial() => setState(
    () => _materials.add({'id': _generateId('mat'), 'name': '', 'qty': 0}),
  );

  void _addProduct() => setState(
    () => _products.add({
      'id': _generateId('prod'),
      'name': '',
      'qty': 0,
      'rate': 0.0,
      'linked_materials': <Map<String, dynamic>>[],
    }),
  );

  // --- AUTO CALCULATION ---
  void _calculateTotal() {
    double total = 0.0;
    for (var p in _products) {
      int qty = p['qty'] ?? 0;
      double rate = p['rate'] ?? 0.0;
      total += (qty * rate);
    }
    _costCtrl.text = total.toInt().toString();
  }

  int _getRemainingQty(String matId, int totalQty) {
    int used = 0;
    for (var prod in _products) {
      for (var link in (prod['linked_materials'] ?? [])) {
        if (link['id'] == matId) {
          used += (link['used_qty'] as int? ?? 0);
        }
      }
    }
    return totalQty - used;
  }

  // --- TEXT-BOX LOGIC FOR LINKING ---
  void _openLinkDialog(int productIndex) {
    final validMaterials = _materials
        .where((m) => m['name'].toString().isNotEmpty)
        .toList();

    if (validMaterials.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Add valid Input Materials first."),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) {
        List<Map<String, dynamic>> tempLinks = List<Map<String, dynamic>>.from(
          (_products[productIndex]['linked_materials'] ?? []).map(
            (e) => Map<String, dynamic>.from(e),
          ),
        );

        Map<String, TextEditingController> textCtrls = {};
        for (var link in tempLinks) {
          textCtrls[link['id']] = TextEditingController(
            text: link['used_qty'].toString(),
          );
        }

        final productName = _products[productIndex]['name']?.toString();
        final displayProduct = (productName != null && productName.trim().isNotEmpty)
            ? productName.trim()
            : "Product #${productIndex + 1}";

        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return Dialog(
              backgroundColor: Colors.transparent,
              elevation: 0,
              insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.16),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Modern Header
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [_primary, _primary.withValues(alpha: 0.9)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.link_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    "Link Input Materials",
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                      color: Colors.white,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    "Allocate materials used to make \"$displayProduct\"",
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFFCBD5E1),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 20),
                              tooltip: "Close",
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        ),
                      ),

                      // Material Cards List
                      Flexible(
                        child: validMaterials.isEmpty
                            ? const Padding(
                                padding: EdgeInsets.all(32),
                                child: Text("No input materials available.", style: TextStyle(color: Colors.grey)),
                              )
                            : ListView.separated(
                                shrinkWrap: true,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                itemCount: validMaterials.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 8),
                                itemBuilder: (ctx, i) {
                                  final mat = validMaterials[i];
                                  final String matId = mat['id'];
                                  final int totalQty = mat['qty'] as int;

                                  int otherUsed = 0;
                                  for (int p = 0; p < _products.length; p++) {
                                    if (p == productIndex) continue;
                                    for (var link in (_products[p]['linked_materials'] ?? [])) {
                                      if (link['id'] == matId) {
                                        otherUsed += (link['used_qty'] as int? ?? 0);
                                      }
                                    }
                                  }
                                  final int maxAvailable = totalQty - otherUsed;

                                  int linkIndex = tempLinks.indexWhere((l) => l['id'] == matId);
                                  bool isSelected = linkIndex != -1;
                                  int currentUsed = isSelected ? (tempLinks[linkIndex]['used_qty'] as int? ?? 1) : 0;

                                  Color cardBg = isSelected ? const Color(0xFFEFF6FF) : const Color(0xFFF8FAFC);
                                  Color cardBorder = isSelected ? const Color(0xFF3B82F6) : const Color(0xFFE2E8F0);

                                  return AnimatedContainer(
                                    duration: const Duration(milliseconds: 180),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: cardBg,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: cardBorder, width: isSelected ? 1.5 : 1.0),
                                    ),
                                    child: Row(
                                      children: [
                                        Checkbox(
                                          value: isSelected,
                                          activeColor: _primary,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                          onChanged: (maxAvailable <= 0 && !isSelected)
                                              ? null
                                              : (val) {
                                                  setStateDialog(() {
                                                    if (val == true) {
                                                      tempLinks.add({'id': matId, 'used_qty': 1});
                                                      textCtrls[matId] = TextEditingController(text: "1");
                                                    } else {
                                                      tempLinks.removeWhere((l) => l['id'] == matId);
                                                      textCtrls.remove(matId);
                                                    }
                                                  });
                                                },
                                        ),
                                        const SizedBox(width: 4),

                                        // Material Details
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                mat['name'],
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 13.5,
                                                  color: isSelected ? const Color(0xFF1E293B) : const Color(0xFF334155),
                                                ),
                                              ),
                                              const SizedBox(height: 3),
                                              Row(
                                                children: [
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: maxAvailable > 0
                                                          ? const Color(0xFFDCFCE7)
                                                          : const Color(0xFFFEE2E2),
                                                      borderRadius: BorderRadius.circular(4),
                                                    ),
                                                    child: Text(
                                                      maxAvailable > 0 ? "Avail: $maxAvailable" : "Depleted",
                                                      style: TextStyle(
                                                        fontSize: 10,
                                                        fontWeight: FontWeight.bold,
                                                        color: maxAvailable > 0
                                                            ? const Color(0xFF166534)
                                                            : const Color(0xFF991B1B),
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    "Total: $totalQty",
                                                    style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),

                                        // Intuitive Stepper Controls
                                        if (isSelected)
                                          Container(
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(color: const Color(0xFFCBD5E1)),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                InkWell(
                                                  onTap: () {
                                                    if (currentUsed > 1) {
                                                      int nextVal = currentUsed - 1;
                                                      textCtrls[matId]?.text = nextVal.toString();
                                                      setStateDialog(() {
                                                        tempLinks[linkIndex]['used_qty'] = nextVal;
                                                      });
                                                    }
                                                  },
                                                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(7)),
                                                  child: const Padding(
                                                    padding: EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                                                    child: Icon(Icons.remove_rounded, size: 14, color: Color(0xFF475569)),
                                                  ),
                                                ),
                                                SizedBox(
                                                  width: 44,
                                                  height: 28,
                                                  child: TextField(
                                                    controller: textCtrls[matId],
                                                    keyboardType: TextInputType.number,
                                                    textAlign: TextAlign.center,
                                                    style: const TextStyle(
                                                      fontSize: 12.5,
                                                      fontWeight: FontWeight.bold,
                                                      color: Color(0xFF0F172A),
                                                    ),
                                                    decoration: const InputDecoration(
                                                      isDense: true,
                                                      contentPadding: EdgeInsets.zero,
                                                      border: InputBorder.none,
                                                    ),
                                                    onChanged: (val) {
                                                      int parsed = int.tryParse(val) ?? 0;
                                                      if (parsed > maxAvailable) {
                                                        parsed = maxAvailable;
                                                        textCtrls[matId]!.text = parsed.toString();
                                                        textCtrls[matId]!.selection = TextSelection.fromPosition(
                                                          TextPosition(offset: textCtrls[matId]!.text.length),
                                                        );
                                                      }
                                                      setStateDialog(() {
                                                        tempLinks[linkIndex]['used_qty'] = parsed;
                                                      });
                                                    },
                                                  ),
                                                ),
                                                InkWell(
                                                  onTap: () {
                                                    if (currentUsed < maxAvailable) {
                                                      int nextVal = currentUsed + 1;
                                                      textCtrls[matId]?.text = nextVal.toString();
                                                      setStateDialog(() {
                                                        tempLinks[linkIndex]['used_qty'] = nextVal;
                                                      });
                                                    }
                                                  },
                                                  borderRadius: const BorderRadius.horizontal(right: Radius.circular(7)),
                                                  child: const Padding(
                                                    padding: EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                                                    child: Icon(Icons.add_rounded, size: 14, color: Color(0xFF475569)),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                      ),

                      // Sticky Action Footer
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        decoration: const BoxDecoration(
                          color: Color(0xFFF8FAFC),
                          border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              "${tempLinks.length} material(s) linked",
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                            ),
                            Row(
                              children: [
                                OutlinedButton(
                                  onPressed: () => Navigator.pop(context),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFF475569),
                                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  child: const Text("Cancel"),
                                ),
                                const SizedBox(width: 10),
                                ElevatedButton.icon(
                                  onPressed: () {
                                    setState(() {
                                      _products[productIndex]['linked_materials'] = tempLinks;
                                    });
                                    Navigator.pop(context);
                                  },
                                  icon: const Icon(Icons.check_rounded, size: 16),
                                  label: const Text("Save Links"),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _primary,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    elevation: 0,
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
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final bool isWideScreen = screenSize.width >= 750;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isWideScreen ? 32 : 10,
        vertical: isWideScreen ? 24 : 12,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 840,
            maxHeight: screenSize.height * (isWideScreen ? 0.88 : 0.94),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 1. Compact Header Bar
              _buildDialogHeader(isWideScreen),

              // 2. Flexible Scrollable Form Body (Shrink-wraps without empty space!)
              Flexible(
                child: Container(
                  color: Colors.white,
                  child: Form(
                    key: _formKey,
                    child: SingleChildScrollView(
                      controller: _formScrollCtrl,
                      primary: false,
                      physics: const AlwaysScrollableScrollPhysics(
                        parent: ClampingScrollPhysics(),
                      ),
                      padding: EdgeInsets.fromLTRB(
                        isWideScreen ? 20 : 12,
                        14,
                        isWideScreen ? 20 : 12,
                        16,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Section A: Client & Order Basics
                          _buildClientSection(isWideScreen),
                          const SizedBox(height: 12),

                          // Section B: Notes / Work Scope
                          _buildWorkDetailsSection(),
                          const SizedBox(height: 14),

                          // Section C: Dual-Column Materials & Products Grid
                          if (isWideScreen)
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Left Column: Materials Input
                                Expanded(child: _buildMaterialsCard(true)),
                                const SizedBox(width: 14),
                                // Right Column: Products Output
                                Expanded(child: _buildProductsCard(true)),
                              ],
                            )
                          else ...[
                            _buildMaterialsCard(false),
                            const SizedBox(height: 14),
                            _buildProductsCard(false),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // 3. Compact Sticky Financials & Action Footer
              _buildDialogFooter(isWideScreen),
            ],
          ),
        ),
      ),
    );
  }

  /// Compact Header Banner
  Widget _buildDialogHeader(bool isWideScreen) {
    return Container(
      padding: EdgeInsets.fromLTRB(isWideScreen ? 20 : 14, 12, 12, 12),
      decoration: const BoxDecoration(
        color: _primary,
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.asset(
                'assets/app.png',
                width: 22,
                height: 22,
                fit: BoxFit.contain,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              "New Job Order",
              style: TextStyle(
                fontSize: isWideScreen ? 16 : 14.5,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 0.3,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),

          // Bill Number Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              "#${_billNoCtrl.text.isEmpty ? '...' : _billNoCtrl.text}",
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),

          const Spacer(),

          // Date Selector Pill
          Tooltip(
            message: "Change Bill Date",
            child: InkWell(
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _billDate,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                );
                if (d != null) setState(() => _billDate = d);
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.calendar_today, size: 13, color: Colors.white70),
                    const SizedBox(width: 5),
                    Text(
                      isWideScreen
                          ? "Bill Date: ${DateFormat('dd MMM yyyy').format(_billDate)}"
                          : DateFormat('dd MMM').format(_billDate),
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Close (X) Button
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white70, size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: "Close",
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildClientAutocompleteField() {
    return Autocomplete<Map<String, dynamic>>(
      initialValue: TextEditingValue(text: _nameCtrl.text),
      optionsBuilder: (v) async => v.text.isEmpty
          ? []
          : await DatabaseHelper.instance.searchClients(v.text),
      displayStringForOption: (o) => o['client_name'].toString(),
      optionsViewOpenDirection: OptionsViewOpenDirection.down,
      onSelected: (o) => setState(() {
        _nameCtrl.text = o['client_name'];
        _phoneCtrl.text = o['client_phone'] ?? "";
        _placeCtrl.text = o['client_place'] ?? "";
      }),
      optionsViewBuilder: (context, onSelected, options) {
        return ScrollableAutocompleteOptions<Map<String, dynamic>>(
          options: options,
          onSelected: onSelected,
          preferredWidth: 300,
          maxHeight: 190,
          itemBuilder: (ctx, option) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  option['client_name']?.toString() ?? '',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
                if (option['client_place'] != null &&
                    option['client_place'].toString().isNotEmpty)
                  Text(
                    option['client_place'].toString(),
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
              ],
            ),
          ),
        );
      },
      fieldViewBuilder: (ctx, ctrl, focus, onEdit) {
        if (!focus.hasFocus && ctrl.text != _nameCtrl.text) {
          ctrl.text = _nameCtrl.text;
        }
        return SizedBox(
          height: 44,
          child: TextFormField(
            controller: ctrl,
            focusNode: focus,
            style: const TextStyle(fontSize: 13.5),
            textCapitalization: TextCapitalization.words,
            decoration: _inputDec("Client Name *", icon: Icons.person_outline),
            onChanged: (v) => _nameCtrl.text = v,
          ),
        );
      },
    );
  }

  Widget _buildDeadlinePickerButton() {
    return InkWell(
      onTap: () async {
        final d = await showDatePicker(
          context: context,
          initialDate: _deadlineDate,
          firstDate: DateTime.now(),
          lastDate: DateTime.now().add(const Duration(days: 365)),
        );
        if (d != null) setState(() => _deadlineDate = d);
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFCBD5E1)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.flag_outlined, size: 16, color: Colors.deepOrange),
            const SizedBox(width: 6),
            Text(
              "Due: ${DateFormat('dd MMM').format(_deadlineDate)}",
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
            ),
          ],
        ),
      ),
    );
  }

  /// Compact Client & Order Basic Details Row (Responsive for Mobile & Desktop)
  Widget _buildClientSection(bool isWideScreen) {
    if (!isWideScreen) {
      return Column(
        children: [
          Row(
            children: [
              Expanded(child: _buildClientAutocompleteField()),
              const SizedBox(width: 8),
              _buildDeadlinePickerButton(),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: TextFormField(
                    controller: _phoneCtrl,
                    style: const TextStyle(fontSize: 13.5),
                    keyboardType: TextInputType.phone,
                    decoration: _inputDec("Phone", icon: Icons.phone_outlined),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: TextFormField(
                    controller: _placeCtrl,
                    style: const TextStyle(fontSize: 13.5),
                    textCapitalization: TextCapitalization.words,
                    decoration: _inputDec("Place", icon: Icons.location_on_outlined),
                  ),
                ),
              ),
            ],
          ),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(flex: 4, child: _buildClientAutocompleteField()),
        const SizedBox(width: 8),
        Expanded(
          flex: 3,
          child: SizedBox(
            height: 44,
            child: TextFormField(
              controller: _phoneCtrl,
              style: const TextStyle(fontSize: 13.5),
              keyboardType: TextInputType.phone,
              decoration: _inputDec("Phone Number", icon: Icons.phone_outlined),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 3,
          child: SizedBox(
            height: 44,
            child: TextFormField(
              controller: _placeCtrl,
              style: const TextStyle(fontSize: 13.5),
              textCapitalization: TextCapitalization.words,
              decoration: _inputDec("Place / City", icon: Icons.location_on_outlined),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _buildDeadlinePickerButton(),
      ],
    );
  }

  /// Compact Work Details Section
  Widget _buildWorkDetailsSection() {
    return SizedBox(
      height: 44,
      child: TextFormField(
        controller: _detailsCtrl,
        maxLines: 1,
        style: const TextStyle(fontSize: 13.5),
        textCapitalization: TextCapitalization.sentences,
        decoration: _inputDec("Work Details / Scope (Optional notes or specifications...)", icon: Icons.description_outlined),
      ),
    );
  }

  /// Compact Materials Card (Raw Input)
  Widget _buildMaterialsCard(bool isWideScreen) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBF5),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: const [
                  Icon(Icons.inventory_2_outlined, size: 16, color: Colors.deepOrange),
                  SizedBox(width: 6),
                  Text(
                    "Materials Input (Raw)",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF9A3412)),
                  ),
                ],
              ),
              InkWell(
                onTap: _addMaterial,
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.deepOrange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: const [
                      Icon(Icons.add, size: 13, color: Colors.deepOrange),
                      SizedBox(width: 3),
                      Text("Add Item", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.deepOrange)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Column Headers (Desktop only; mobile uses labeled compact stacked layout)
          if (isWideScreen)
            Padding(
              padding: const EdgeInsets.only(left: 4, right: 4, bottom: 6),
              child: Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: Text(
                      "MATERIAL NAME",
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey.shade600, letterSpacing: 0.5),
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 64,
                    child: Text(
                      "QTY",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey.shade600, letterSpacing: 0.5),
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 60,
                    child: Text(
                      "LEFT",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey.shade600, letterSpacing: 0.5),
                    ),
                  ),
                  if (_materials.length > 1) const SizedBox(width: 24),
                ],
              ),
            ),

          // Items List
          ..._materials.asMap().entries.map((entry) => _buildCompactMaterialRow(entry.key, isWideScreen)),
        ],
      ),
    );
  }

  Widget _buildMaterialNameAutocomplete(int index, bool isWideScreen) {
    return Autocomplete<String>(
      key: ValueKey("mat_ac_${_materials[index]['id']}"),
      initialValue: TextEditingValue(text: _materials[index]['name'] ?? ''),
      optionsBuilder: (v) => v.text.isEmpty
          ? const Iterable.empty()
          : _knownItems.where((o) => o.toLowerCase().contains(v.text.toLowerCase())),
      optionsViewOpenDirection: isWideScreen
          ? OptionsViewOpenDirection.mostSpace
          : OptionsViewOpenDirection.up,
      onSelected: (s) => setState(() => _materials[index]['name'] = s),
      optionsViewBuilder: (context, onSelected, options) {
        return ScrollableAutocompleteOptions<String>(
          options: options,
          onSelected: onSelected,
          preferredWidth: isWideScreen ? 280 : null,
          maxHeight: 190,
          itemBuilder: (ctx, option) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Text(
              option,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
                color: Color(0xFF1E293B),
              ),
            ),
          ),
        );
      },
      fieldViewBuilder: (ctx, ctrl, focus, submit) {
        if (!focus.hasFocus && ctrl.text != (_materials[index]['name'] ?? '')) {
          ctrl.text = _materials[index]['name'] ?? '';
        }
        return SizedBox(
          height: 42,
          child: TextFormField(
            controller: ctrl,
            focusNode: focus,
            style: const TextStyle(fontSize: 13),
            textCapitalization: TextCapitalization.words,
            decoration: _miniFieldDec("e.g. Iron Pipe 2\""),
            onChanged: (v) => _materials[index]['name'] = v,
          ),
        );
      },
    );
  }

  Widget _buildCompactMaterialRow(int index, bool isWideScreen) {
    int totalQty = _materials[index]['qty'];
    int remaining = _getRemainingQty(_materials[index]['id'], totalQty);

    final qtyField = SizedBox(
      width: isWideScreen ? 68 : null,
      height: 42,
      child: TextFormField(
        initialValue: _materials[index]['qty'] == 0 ? null : _materials[index]['qty'].toString(),
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
        decoration: _miniFieldDec(isWideScreen ? "0" : "Qty: 0"),
        onChanged: (v) => setState(() => _materials[index]['qty'] = int.tryParse(v) ?? 0),
      ),
    );

    final remBadge = Container(
      width: isWideScreen ? 64 : null,
      height: 42,
      padding: isWideScreen ? null : const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: remaining > 0 ? const Color(0xFFDCFCE7) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: remaining > 0 ? const Color(0xFF86EFAC) : const Color(0xFFCBD5E1)),
      ),
      child: Text(
        isWideScreen ? "$remaining" : "Left: $remaining",
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.bold,
          color: remaining > 0 ? const Color(0xFF166534) : const Color(0xFF64748B),
        ),
      ),
    );

    final removeBtn = _materials.length > 1
        ? Padding(
            padding: const EdgeInsets.only(left: 4),
            child: IconButton(
              icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent, size: 18),
              splashRadius: 16,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              onPressed: () => setState(() => _materials.removeAt(index)),
            ),
          )
        : const SizedBox.shrink();

    if (!isWideScreen) {
      return Container(
        key: ValueKey("mat_row_${_materials[index]['id']}"),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.orange.withValues(alpha: 0.25)),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(child: _buildMaterialNameAutocomplete(index, false)),
                removeBtn,
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(child: qtyField),
                const SizedBox(width: 8),
                Expanded(child: remBadge),
              ],
            ),
          ],
        ),
      );
    }

    return Padding(
      key: ValueKey("mat_row_${_materials[index]['id']}"),
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(flex: 5, child: _buildMaterialNameAutocomplete(index, true)),
          const SizedBox(width: 6),
          qtyField,
          const SizedBox(width: 6),
          remBadge,
          removeBtn,
        ],
      ),
    );
  }

  /// Compact Products Card (To Make)
  Widget _buildProductsCard(bool isWideScreen) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF0F7FF),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: const [
                  Icon(Icons.precision_manufacturing_outlined, size: 16, color: Color(0xFF1D4ED8)),
                  SizedBox(width: 6),
                  Text(
                    "Products Output (To Make)",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E40AF)),
                  ),
                ],
              ),
              InkWell(
                onTap: _addProduct,
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1D4ED8).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: const [
                      Icon(Icons.add, size: 13, color: Color(0xFF1D4ED8)),
                      SizedBox(width: 3),
                      Text("Add Product", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1D4ED8))),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Column Headers (Desktop only)
          if (isWideScreen)
            Padding(
              padding: const EdgeInsets.only(left: 4, right: 4, bottom: 6),
              child: Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: Text(
                      "PRODUCT NAME",
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey.shade600, letterSpacing: 0.5),
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 58,
                    child: Text(
                      "QTY",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey.shade600, letterSpacing: 0.5),
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 78,
                    child: Text(
                      "₹ RATE",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey.shade600, letterSpacing: 0.5),
                    ),
                  ),
                  if (_products.length > 1) const SizedBox(width: 24),
                ],
              ),
            ),

          // Products List
          ..._products.asMap().entries.map((entry) => _buildCompactProductRow(entry.key, isWideScreen)),
        ],
      ),
    );
  }

  Widget _buildProductNameAutocomplete(int index, bool isWideScreen) {
    return Autocomplete<String>(
      key: ValueKey("prod_ac_${_products[index]['id']}"),
      initialValue: TextEditingValue(text: _products[index]['name'] ?? ''),
      optionsBuilder: (v) => v.text.isEmpty
          ? const Iterable.empty()
          : _knownItems.where((o) => o.toLowerCase().contains(v.text.toLowerCase())),
      optionsViewOpenDirection: isWideScreen
          ? OptionsViewOpenDirection.mostSpace
          : OptionsViewOpenDirection.up,
      onSelected: (s) {
        setState(() {
          _products[index]['name'] = s;
          if (_historicalRates.containsKey(s)) {
            _products[index]['rate'] = _historicalRates[s];
            _calculateTotal();
          }
        });
      },
      optionsViewBuilder: (context, onSelected, options) {
        return ScrollableAutocompleteOptions<String>(
          options: options,
          onSelected: onSelected,
          preferredWidth: isWideScreen ? 280 : null,
          maxHeight: 190,
          itemBuilder: (ctx, option) {
            final rate = _historicalRates[option];
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      option,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF1E293B),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (rate != null && rate > 0)
                    Text(
                      "₹${rate.toStringAsFixed(0)}",
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1D4ED8),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
      fieldViewBuilder: (ctx, ctrl, focus, submit) {
        if (!focus.hasFocus && ctrl.text != (_products[index]['name'] ?? '')) {
          ctrl.text = _products[index]['name'] ?? '';
        }
        return SizedBox(
          height: 42,
          child: TextFormField(
            controller: ctrl,
            focusNode: focus,
            style: const TextStyle(fontSize: 13),
            textCapitalization: TextCapitalization.words,
            decoration: _miniFieldDec("e.g. Window Grill"),
            onChanged: (v) {
              _products[index]['name'] = v;
              final matched = _historicalRates.keys.firstWhere(
                (k) => k.toLowerCase() == v.trim().toLowerCase(),
                orElse: () => "",
              );
              if (matched.isNotEmpty) {
                setState(() {
                  _products[index]['rate'] = _historicalRates[matched];
                  _calculateTotal();
                });
              }
            },
          ),
        );
      },
    );
  }

  Widget _buildCompactProductRow(int index, bool isWideScreen) {
    final List links = _products[index]['linked_materials'] ?? [];
    final linkedCount = links.length;
    final isLinked = linkedCount > 0;

    int qty = _products[index]['qty'] ?? 0;
    double rate = _products[index]['rate'] ?? 0.0;
    double rowTotal = qty * rate;

    final qtyField = SizedBox(
      width: isWideScreen ? 64 : null,
      height: 42,
      child: TextFormField(
        initialValue: _products[index]['qty'] == 0 ? null : _products[index]['qty'].toString(),
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
        decoration: _miniFieldDec(isWideScreen ? "0" : "Qty: 0"),
        onChanged: (v) {
          setState(() {
            _products[index]['qty'] = int.tryParse(v) ?? 0;
            _calculateTotal();
          });
        },
      ),
    );

    final rateField = SizedBox(
      width: isWideScreen ? 84 : null,
      height: 42,
      child: TextFormField(
        key: ValueKey("rate_${_products[index]['id']}_${_products[index]['name']}"),
        initialValue: _products[index]['rate'] == 0.0 ? null : _products[index]['rate'].toString(),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
        decoration: _miniFieldDec("0.0", prefixText: "₹"),
        onChanged: (v) {
          setState(() {
            _products[index]['rate'] = double.tryParse(v) ?? 0.0;
            _calculateTotal();
          });
        },
      ),
    );

    final removeBtn = _products.length > 1
        ? Padding(
            padding: const EdgeInsets.only(left: 4),
            child: IconButton(
              icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent, size: 18),
              splashRadius: 16,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              onPressed: () => setState(() {
                _products.removeAt(index);
                _calculateTotal();
              }),
            ),
          )
        : const SizedBox.shrink();

    final linkSubRow = Padding(
      padding: const EdgeInsets.only(top: 6, left: 2, right: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          InkWell(
            onTap: () => _openLinkDialog(index),
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: isLinked ? const Color(0xFFDBEAFE) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: isLinked ? const Color(0xFF93C5FD) : const Color(0xFFCBD5E1)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.link, size: 13, color: isLinked ? _primary : Colors.grey[700]),
                  const SizedBox(width: 4),
                  Text(
                    isLinked ? "Uses $linkedCount materials" : "Link materials...",
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: isLinked ? FontWeight.bold : FontWeight.w500,
                      color: isLinked ? _primary : Colors.grey[700],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (rowTotal > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFDCFCE7),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                "= ₹${rowTotal.toStringAsFixed(0)}",
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF166534)),
              ),
            ),
        ],
      ),
    );

    if (!isWideScreen) {
      return Container(
        key: ValueKey("prod_row_${_products[index]['id']}"),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.blue.withValues(alpha: 0.25)),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(child: _buildProductNameAutocomplete(index, false)),
                removeBtn,
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(child: qtyField),
                const SizedBox(width: 8),
                Expanded(child: rateField),
              ],
            ),
            linkSubRow,
          ],
        ),
      );
    }

    return Padding(
      key: ValueKey("prod_row_${_products[index]['id']}"),
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(flex: 5, child: _buildProductNameAutocomplete(index, true)),
              const SizedBox(width: 6),
              qtyField,
              const SizedBox(width: 6),
              rateField,
              removeBtn,
            ],
          ),
          linkSubRow,
        ],
      ),
    );
  }

  /// Compact Sticky Dialog Footer (Responsive for Mobile & Desktop)
  Widget _buildDialogFooter(bool isWideScreen) {
    double cost = double.tryParse(_costCtrl.text) ?? 0.0;
    double advance = double.tryParse(_advanceCtrl.text) ?? 0.0;
    double balance = cost - advance;

    final costField = SizedBox(
      width: isWideScreen ? 155 : null,
      height: isWideScreen ? 48 : 42,
      child: TextFormField(
        controller: _costCtrl,
        keyboardType: TextInputType.number,
        style: TextStyle(
          fontSize: isWideScreen ? 14.5 : 13.5,
          fontWeight: FontWeight.bold,
          color: const Color(0xFF0F172A),
        ),
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.currency_rupee, size: 16, color: Colors.blueGrey),
          prefixIconConstraints: const BoxConstraints(minWidth: 30),
          hintText: "Total Cost",
          hintStyle: TextStyle(fontSize: 12.5, fontWeight: FontWeight.normal, color: Colors.grey.shade400),
          isDense: true,
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _primary, width: 1.5)),
        ),
        onChanged: (_) => setState(() {}),
      ),
    );

    final advanceField = SizedBox(
      width: isWideScreen ? 145 : null,
      height: isWideScreen ? 48 : 42,
      child: TextFormField(
        controller: _advanceCtrl,
        keyboardType: TextInputType.number,
        style: TextStyle(
          fontSize: isWideScreen ? 14.5 : 13.5,
          fontWeight: FontWeight.bold,
          color: const Color(0xFF0F172A),
        ),
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.payments_outlined, size: 16, color: Colors.blueGrey),
          prefixIconConstraints: const BoxConstraints(minWidth: 30),
          hintText: "Advance",
          hintStyle: TextStyle(fontSize: 12.5, fontWeight: FontWeight.normal, color: Colors.grey.shade400),
          isDense: true,
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _primary, width: 1.5)),
        ),
        onChanged: (_) => setState(() {}),
      ),
    );

    final balancePill = Container(
      height: isWideScreen ? 48 : 42,
      padding: EdgeInsets.symmetric(horizontal: isWideScreen ? 14 : 10),
      decoration: BoxDecoration(
        color: balance > 0 ? const Color(0xFFFEF3C7) : const Color(0xFFDCFCE7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: balance > 0 ? const Color(0xFFFCD34D) : const Color(0xFF86EFAC)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            balance > 0 ? "Bal: " : "Paid: ",
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: balance > 0 ? const Color(0xFF92400E) : const Color(0xFF166534),
            ),
          ),
          Text(
            "₹${balance.toStringAsFixed(0)}",
            style: TextStyle(
              fontSize: isWideScreen ? 14.5 : 13,
              fontWeight: FontWeight.bold,
              color: balance > 0 ? const Color(0xFF92400E) : const Color(0xFF166534),
            ),
          ),
        ],
      ),
    );

    final cancelBtn = TextButton(
      onPressed: () => Navigator.pop(context),
      style: TextButton.styleFrom(
        foregroundColor: Colors.grey.shade700,
        padding: EdgeInsets.symmetric(horizontal: isWideScreen ? 18 : 12, vertical: 12),
        minimumSize: Size(0, isWideScreen ? 48 : 42),
      ),
      child: const Text("Cancel", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
    );

    final submitBtn = ElevatedButton.icon(
      onPressed: _save,
      icon: const Icon(Icons.check_circle_outline, size: 18),
      label: const Text(
        "CREATE JOB ORDER",
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.3),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: _accent,
        foregroundColor: Colors.white,
        minimumSize: Size(0, isWideScreen ? 48 : 42),
        padding: EdgeInsets.symmetric(horizontal: isWideScreen ? 22 : 14, vertical: 11),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        elevation: 1,
      ),
    );

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isWideScreen ? 20 : 12,
        vertical: isWideScreen ? 12 : 10,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: isWideScreen
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                costField,
                const SizedBox(width: 10),
                advanceField,
                const SizedBox(width: 10),
                balancePill,
                const Spacer(),
                cancelBtn,
                const SizedBox(width: 8),
                submitBtn,
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(flex: 3, child: costField),
                    const SizedBox(width: 6),
                    Expanded(flex: 3, child: advanceField),
                    const SizedBox(width: 6),
                    balancePill,
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    cancelBtn,
                    const SizedBox(width: 8),
                    Expanded(child: submitBtn),
                  ],
                ),
              ],
            ),
    );
  }

  InputDecoration _inputDec(String hint, {IconData? icon}) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
    prefixIcon: icon != null ? Icon(icon, size: 18, color: Colors.blueGrey) : null,
    isDense: true,
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: _primary, width: 1.5),
    ),
  );

  InputDecoration _miniFieldDec(String hint, {String? prefixText}) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(fontSize: 12.5, color: Colors.grey.shade400),
    prefixText: prefixText,
    prefixStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
    isDense: true,
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: _primary, width: 1.5),
    ),
  );

  void _save() async {
    HapticFeedback.lightImpact();
    if (!_formKey.currentState!.validate()) return;
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("Please enter Client Name"),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
      return;
    }

    final finalMaterials = _materials
        .where((e) => e['name'].toString().isNotEmpty)
        .toList();
    final finalProducts = _products
        .where((e) => e['name'].toString().isNotEmpty)
        .toList();

    if (finalProducts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("Add at least one product"),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
      return;
    }

    if (_billNoCtrl.text.trim().isEmpty) {
      _billNoCtrl.text = await DatabaseHelper.instance.generateNextBillNumber();
    }

    int totalMatQty = finalMaterials.fold(
      0,
      (sum, item) => sum + (item['qty'] as int),
    );
    int totalProdQty = finalProducts.fold(
      0,
      (sum, item) => sum + (item['qty'] as int),
    );

    String matSummary = finalMaterials.isNotEmpty
        ? finalMaterials[0]['name']
        : "-";
    if (finalMaterials.length > 1) {
      matSummary += " +${finalMaterials.length - 1} more";
    }

    String prodSummary = finalProducts[0]['name'];
    if (finalProducts.length > 1) {
      prodSummary += " +${finalProducts.length - 1} more";
    }

    int jobId = await DatabaseHelper.instance.createJob({
      'bill_no': _billNoCtrl.text,
      'client_name': _nameCtrl.text,
      'client_place': _placeCtrl.text,
      'client_phone': _phoneCtrl.text,
      'material_brought': matSummary,
      'qty_given': totalMatQty,
      'product_type': prodSummary,
      'target_qty': totalProdQty,
      'items': jsonEncode({"in": finalMaterials, "out": finalProducts}),
      'work_details': _detailsCtrl.text,
      'total_cost': double.tryParse(_costCtrl.text) ?? 0,
      'created_at': _billDate.toIso8601String(),
      'deadline_date': _deadlineDate.toIso8601String(),
      'status': 'Nothing',
    });

    double adv = double.tryParse(_advanceCtrl.text) ?? 0;
    if (adv > 0) {
      await DatabaseHelper.instance.addPayment(jobId, adv, "Advance");
    }

    ref.invalidate(activeJobsProvider);
    if (mounted) Navigator.pop(context, true);
  }
}
