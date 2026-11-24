import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import '../database_helper.dart';
import '../providers.dart';

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

        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              clipBehavior: Clip.antiAlias,
              titlePadding: EdgeInsets.zero,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              title: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: const BoxDecoration(
                  color: _primary,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Row(
                  children: const [
                    Icon(Icons.link, color: Colors.white, size: 20),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        "Link Input Materials",
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
              content: SizedBox(
                width: 450,
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: validMaterials.length,
                  separatorBuilder: (ctx, i) => const Divider(height: 1, indent: 40),
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

                    int linkIndex = tempLinks.indexWhere(
                      (l) => l['id'] == matId,
                    );
                    bool isSelected = linkIndex != -1;

                    return ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
                      leading: Checkbox(
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
                      title: Text(
                        mat['name'],
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      subtitle: Text(
                        "Available: $maxAvailable / Total: $totalQty",
                        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                      ),
                      trailing: isSelected
                          ? SizedBox(
                              width: 65,
                              child: TextField(
                                controller: textCtrls[matId],
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 12),
                                decoration: InputDecoration(
                                  isDense: true,
                                  filled: true,
                                  fillColor: Colors.grey[50],
                                  contentPadding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
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
                            )
                          : null,
                    );
                  },
                ),
              ),
              actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _products[productIndex]['linked_materials'] = tempLinks;
                    });
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text("Save Links"),
                ),
              ],
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
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      clipBehavior: Clip.antiAlias,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isWideScreen ? 32 : 16,
        vertical: 24,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 820,
          maxHeight: screenSize.height * 0.90,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 1. Compact Header Bar
            _buildDialogHeader(),

            // 2. Scrollable Compact Form Body
            Expanded(
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Section A: Client & Order Basics
                      _buildClientSection(),
                      const SizedBox(height: 14),

                      // Section B: Notes / Work Scope
                      TextFormField(
                        controller: _detailsCtrl,
                        maxLines: 1,
                        style: const TextStyle(fontSize: 13),
                        textCapitalization: TextCapitalization.sentences,
                        decoration: _inputDec("Work Details / Scope (Optional)", icon: Icons.description_outlined),
                      ),
                      const SizedBox(height: 16),

                      // Section C: Dual-Column Materials & Products Grid
                      if (isWideScreen)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Left Column: Materials Input
                            Expanded(child: _buildMaterialsCard()),
                            const SizedBox(width: 14),
                            // Right Column: Products Output
                            Expanded(child: _buildProductsCard()),
                          ],
                        )
                      else ...[
                        _buildMaterialsCard(),
                        const SizedBox(height: 14),
                        _buildProductsCard(),
                      ],
                    ],
                  ),
                ),
              ),
            ),

            // 3. Compact Sticky Financials & Action Footer
            _buildDialogFooter(),
          ],
        ),
      ),
    );
  }

  /// Compact Header Banner
  Widget _buildDialogHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
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
                'assets/Logo.png',
                width: 22,
                height: 22,
                fit: BoxFit.contain,
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Text(
            "New Job Order",
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 12),

          // Bill Number Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              "#${_billNoCtrl.text.isEmpty ? '...' : _billNoCtrl.text}",
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),

          const Spacer(),

          // Date Selector Pill
          InkWell(
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
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today, size: 13, color: Colors.white70),
                  const SizedBox(width: 6),
                  Text(
                    DateFormat('dd MMM yyyy').format(_billDate),
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ],
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

  /// Compact Client & Order Basic Details Row
  Widget _buildClientSection() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Client Name (Autocomplete)
        Expanded(
          flex: 4,
          child: Autocomplete<Map<String, dynamic>>(
            optionsBuilder: (v) async => v.text.isEmpty
                ? []
                : await DatabaseHelper.instance.searchClients(v.text),
            displayStringForOption: (o) => o['client_name'].toString(),
            onSelected: (o) => setState(() {
              _nameCtrl.text = o['client_name'];
              _phoneCtrl.text = o['client_phone'] ?? "";
              _placeCtrl.text = o['client_place'] ?? "";
            }),
            optionsViewBuilder: (context, onSelected, options) {
              return Align(
                alignment: Alignment.topLeft,
                child: Material(
                  elevation: 6,
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(color: Colors.grey.shade200),
                  ),
                  child: Container(
                    width: 260,
                    constraints: const BoxConstraints(maxHeight: 180),
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      shrinkWrap: true,
                      itemCount: options.length,
                      itemBuilder: (BuildContext context, int index) {
                        final option = options.elementAt(index);
                        return InkWell(
                          onTap: () => onSelected(option),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  option['client_name']?.toString() ?? '',
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                ),
                                if (option['client_place'] != null && option['client_place'].toString().isNotEmpty)
                                  Text(
                                    option['client_place'].toString(),
                                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              );
            },
            fieldViewBuilder: (ctx, ctrl, focus, onEdit) {
              if (ctrl.text.isEmpty && _nameCtrl.text.isNotEmpty) {
                ctrl.text = _nameCtrl.text;
              }
              return TextFormField(
                controller: ctrl,
                focusNode: focus,
                style: const TextStyle(fontSize: 13),
                textCapitalization: TextCapitalization.words,
                decoration: _inputDec("Client Name *", icon: Icons.person_outline),
                onChanged: (v) => _nameCtrl.text = v,
                validator: (v) => v!.isEmpty ? "Required" : null,
              );
            },
          ),
        ),
        const SizedBox(width: 10),

        // 2. Phone
        Expanded(
          flex: 3,
          child: TextFormField(
            controller: _phoneCtrl,
            style: const TextStyle(fontSize: 13),
            keyboardType: TextInputType.phone,
            decoration: _inputDec("Phone", icon: Icons.phone_outlined),
          ),
        ),
        const SizedBox(width: 10),

        // 3. Location / Place
        Expanded(
          flex: 3,
          child: TextFormField(
            controller: _placeCtrl,
            style: const TextStyle(fontSize: 13),
            textCapitalization: TextCapitalization.words,
            decoration: _inputDec("Place", icon: Icons.location_on_outlined),
          ),
        ),
        const SizedBox(width: 10),

        // 4. Deadline Date Picker
        InkWell(
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
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Row(
              children: [
                const Icon(Icons.flag_outlined, size: 16, color: Colors.deepOrange),
                const SizedBox(width: 6),
                Text(
                  "Due: ${DateFormat('dd MMM').format(_deadlineDate)}",
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Compact Materials Card (Raw Input)
  Widget _buildMaterialsCard() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        border: Border.all(color: Colors.orange.withOpacity(0.35)),
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
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Row(
                    children: const [
                      Icon(Icons.add, size: 14, color: Colors.deepOrange),
                      SizedBox(width: 2),
                      Text("Add Item", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.deepOrange)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Items List
          ..._materials.asMap().entries.map((entry) => _buildCompactMaterialRow(entry.key)),
        ],
      ),
    );
  }

  Widget _buildCompactMaterialRow(int index) {
    int totalQty = _materials[index]['qty'];
    int remaining = _getRemainingQty(_materials[index]['id'], totalQty);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        children: [
          // Name Autocomplete
          Expanded(
            flex: 4,
            child: Autocomplete<String>(
              optionsBuilder: (v) => v.text.isEmpty
                  ? const Iterable.empty()
                  : _knownItems.where((o) => o.toLowerCase().contains(v.text.toLowerCase())),
              onSelected: (s) => setState(() => _materials[index]['name'] = s),
              fieldViewBuilder: (ctx, ctrl, focus, submit) {
                if (ctrl.text != _materials[index]['name']) {
                  ctrl.text = _materials[index]['name'];
                }
                return TextFormField(
                  controller: ctrl,
                  focusNode: focus,
                  style: const TextStyle(fontSize: 12),
                  textCapitalization: TextCapitalization.words,
                  decoration: _miniFieldDec("Material / Item Name"),
                  onChanged: (v) => _materials[index]['name'] = v,
                );
              },
            ),
          ),
          const SizedBox(width: 6),

          // Quantity
          Expanded(
            flex: 2,
            child: TextFormField(
              initialValue: _materials[index]['qty'] == 0 ? null : _materials[index]['qty'].toString(),
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 12),
              decoration: _miniFieldDec("Qty"),
              onChanged: (v) => setState(() => _materials[index]['qty'] = int.tryParse(v) ?? 0),
            ),
          ),
          const SizedBox(width: 6),

          // Remaining Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: remaining > 0 ? Colors.green[50] : Colors.grey[100],
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: remaining > 0 ? Colors.green[200]! : Colors.grey[300]!),
            ),
            child: Text(
              "Left: $remaining",
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: remaining > 0 ? Colors.green[800] : Colors.grey[600]),
            ),
          ),

          if (_materials.length > 1)
            IconButton(
              icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent, size: 16),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () => setState(() => _materials.removeAt(index)),
            ),
        ],
      ),
    );
  }

  /// Compact Products Card (To Make)
  Widget _buildProductsCard() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        border: Border.all(color: Colors.blue.withOpacity(0.35)),
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
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Row(
                    children: const [
                      Icon(Icons.add, size: 14, color: Color(0xFF1D4ED8)),
                      SizedBox(width: 2),
                      Text("Add Product", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1D4ED8))),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Products List
          ..._products.asMap().entries.map((entry) => _buildCompactProductRow(entry.key)),
        ],
      ),
    );
  }

  Widget _buildCompactProductRow(int index) {
    final List links = _products[index]['linked_materials'] ?? [];
    final linkedCount = links.length;
    final isLinked = linkedCount > 0;

    int qty = _products[index]['qty'] ?? 0;
    double rate = _products[index]['rate'] ?? 0.0;
    double rowTotal = qty * rate;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Column(
        children: [
          Row(
            children: [
              // Product Name Autocomplete
              Expanded(
                flex: 4,
                child: Autocomplete<String>(
                  optionsBuilder: (v) => v.text.isEmpty
                      ? const Iterable.empty()
                      : _knownItems.where((o) => o.toLowerCase().contains(v.text.toLowerCase())),
                  onSelected: (s) {
                    setState(() {
                      _products[index]['name'] = s;
                      if (_historicalRates.containsKey(s)) {
                        _products[index]['rate'] = _historicalRates[s];
                        _calculateTotal();
                      }
                    });
                  },
                  fieldViewBuilder: (ctx, ctrl, focus, submit) {
                    if (ctrl.text != _products[index]['name']) {
                      ctrl.text = _products[index]['name'];
                    }
                    return TextFormField(
                      controller: ctrl,
                      focusNode: focus,
                      style: const TextStyle(fontSize: 12),
                      textCapitalization: TextCapitalization.words,
                      decoration: _miniFieldDec("Product Name"),
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
                    );
                  },
                ),
              ),
              const SizedBox(width: 6),

              // Qty
              Expanded(
                flex: 2,
                child: TextFormField(
                  initialValue: _products[index]['qty'] == 0 ? null : _products[index]['qty'].toString(),
                  keyboardType: TextInputType.number,
                  style: const TextStyle(fontSize: 12),
                  decoration: _miniFieldDec("Qty"),
                  onChanged: (v) {
                    setState(() {
                      _products[index]['qty'] = int.tryParse(v) ?? 0;
                      _calculateTotal();
                    });
                  },
                ),
              ),
              const SizedBox(width: 6),

              // Rate
              Expanded(
                flex: 2,
                child: TextFormField(
                  key: ValueKey("rate_${_products[index]['id']}_${_products[index]['name']}"),
                  initialValue: _products[index]['rate'] == 0.0 ? null : _products[index]['rate'].toString(),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(fontSize: 12),
                  decoration: _miniFieldDec("₹ Rate"),
                  onChanged: (v) {
                    setState(() {
                      _products[index]['rate'] = double.tryParse(v) ?? 0.0;
                      _calculateTotal();
                    });
                  },
                ),
              ),

              if (_products.length > 1)
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent, size: 16),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => setState(() {
                    _products.removeAt(index);
                    _calculateTotal();
                  }),
                ),
            ],
          ),

          // Mini Sub-row: Links & Total
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 2, right: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                InkWell(
                  onTap: () => _openLinkDialog(index),
                  borderRadius: BorderRadius.circular(4),
                  child: Row(
                    children: [
                      Icon(Icons.link, size: 13, color: isLinked ? _primary : Colors.grey),
                      const SizedBox(width: 4),
                      Text(
                        isLinked ? "Uses $linkedCount materials" : "Link materials...",
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: isLinked ? FontWeight.bold : FontWeight.normal,
                          color: isLinked ? _primary : Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                if (rowTotal > 0)
                  Text(
                    "= ₹${rowTotal.toStringAsFixed(0)}",
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green[800]),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Compact Sticky Dialog Footer
  Widget _buildDialogFooter() {
    double cost = double.tryParse(_costCtrl.text) ?? 0.0;
    double advance = double.tryParse(_advanceCtrl.text) ?? 0.0;
    double balance = cost - advance;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          // Total Cost Input
          SizedBox(
            width: 130,
            child: TextFormField(
              controller: _costCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                labelText: "Total Cost",
                prefixText: "₹ ",
                isDense: true,
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 10),

          // Advance Input
          SizedBox(
            width: 120,
            child: TextFormField(
              controller: _advanceCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                labelText: "Advance",
                prefixText: "₹ ",
                isDense: true,
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 10),

          // Balance Due Pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: balance > 0 ? Colors.amber[50] : Colors.green[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: balance > 0 ? Colors.amber[300]! : Colors.green[300]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("Balance Due", style: TextStyle(fontSize: 9, color: Colors.grey)),
                Text(
                  "₹${balance.toStringAsFixed(0)}",
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: balance > 0 ? Colors.amber[900] : Colors.green[900],
                  ),
                ),
              ],
            ),
          ),

          const Spacer(),

          // Cancel
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          const SizedBox(width: 10),

          // Submit CTA
          ElevatedButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check_circle_outline, size: 18),
            label: const Text(
              "CREATE JOB ORDER",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 2,
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDec(String label, {IconData? icon}) => InputDecoration(
    labelText: label,
    prefixIcon: icon != null ? Icon(icon, size: 18) : null,
    isDense: true,
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: Colors.grey.shade300),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: Colors.grey.shade300),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: _primary, width: 1.5),
    ),
  );

  InputDecoration _miniFieldDec(String label) => InputDecoration(
    labelText: label,
    isDense: true,
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(6),
      borderSide: BorderSide(color: Colors.grey.shade300),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(6),
      borderSide: BorderSide(color: Colors.grey.shade300),
    ),
  );

  void _save() async {
    HapticFeedback.lightImpact();
    if (!_formKey.currentState!.validate()) return;
    if (_nameCtrl.text.isEmpty) return;

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
