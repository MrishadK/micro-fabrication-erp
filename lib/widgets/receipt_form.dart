import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import '../database_helper.dart';
import '../providers.dart';

class ReceiptForm extends ConsumerStatefulWidget {
  const ReceiptForm({super.key});

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

  @override
  void initState() {
    super.initState();
    _loadSuggestions();
    _loadNextBillNumber();
    _addMaterial();
    _addProduct();
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

  // --- Gets Remaining Qty for an Input Material ---
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

        // Controllers for the input boxes
        Map<String, TextEditingController> textCtrls = {};
        for (var link in tempLinks) {
          textCtrls[link['id']] = TextEditingController(
            text: link['used_qty'].toString(),
          );
        }

        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              clipBehavior: Clip.antiAlias,
              titlePadding: EdgeInsets.zero,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              title: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  color: Color(0xFF1A237E),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Row(
                  children: const [
                    Icon(Icons.link, color: Colors.white, size: 24),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        "Select Materials",
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: validMaterials.length,
                  separatorBuilder: (ctx, i) => const Divider(height: 1, indent: 40),
                  itemBuilder: (ctx, i) {
                    final mat = validMaterials[i];
                    final String matId = mat['id'];
                    final int totalQty = mat['qty'] as int;

                    // Calculate how much of this material is used by OTHER products
                    int otherUsed = 0;
                    for (int p = 0; p < _products.length; p++) {
                      if (p == productIndex) continue;
                      for (var link
                          in (_products[p]['linked_materials'] ?? [])) {
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
                      contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                      leading: Checkbox(
                        value: isSelected,
                        activeColor: const Color(0xFF1A237E),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                        onChanged: (maxAvailable <= 0 && !isSelected)
                            ? null
                            : (val) {
                                setStateDialog(() {
                                  if (val == true) {
                                    tempLinks.add({'id': matId, 'used_qty': 1});
                                    textCtrls[matId] = TextEditingController(
                                      text: "1",
                                    );
                                  } else {
                                    tempLinks.removeWhere(
                                      (l) => l['id'] == matId,
                                    );
                                    textCtrls.remove(matId);
                                  }
                                });
                              },
                      ),
                      title: Text(
                        mat['name'],
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        "Available: $maxAvailable / Total: $totalQty",
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                      trailing: isSelected
                          ? SizedBox(
                              width: 70,
                              child: TextField(
                                controller: textCtrls[matId],
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                decoration: InputDecoration(
                                  isDense: true,
                                  filled: true,
                                  fillColor: Colors.grey[50],
                                  contentPadding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                    horizontal: 8,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(color: Colors.grey[300]!),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(color: Colors.grey[300]!),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: const BorderSide(color: Color(0xFF1A237E)),
                                  ),
                                ),
                                onChanged: (val) {
                                  int parsed = int.tryParse(val) ?? 0;

                                  // --- CAP TO MAX AVAILABLE ---
                                  if (parsed > maxAvailable) {
                                    parsed = maxAvailable;
                                    textCtrls[matId]!.text = parsed.toString();
                                    textCtrls[matId]!
                                        .selection = TextSelection.fromPosition(
                                      TextPosition(
                                        offset: textCtrls[matId]!.text.length,
                                      ),
                                    );
                                  }

                                  // Update the backend data
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
              actionsPadding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(foregroundColor: Colors.grey[700]),
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
                    backgroundColor: const Color(0xFF1A237E),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                  child: const Text("Save Links", style: TextStyle(fontWeight: FontWeight.bold)),
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
    return Scaffold(
      appBar: AppBar(
        title: const Text("New Job Order"),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      // 🔥 ADDED SAFEAREA HERE TO AVOID THE NAV BAR
      body: SafeArea(
        bottom: true,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            // 🔥 ADDED EXTRA BOTTOM PADDING SO IT DOESN'T HUG THE EDGE
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _billNoCtrl,
                        decoration: const InputDecoration(
                          labelText: "Bill No (Auto)",
                          filled: true,
                          fillColor: Color(0xFFE3F2FD),
                        ),
                      ),
                    ),
                    const SizedBox(width: 15),
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
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          DateFormat('dd MMM').format(_billDate),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Autocomplete<Map<String, dynamic>>(
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
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Colors.grey.shade200),
                        ),
                        child: Container(
                          width: 280,
                          constraints: const BoxConstraints(maxHeight: 220),
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            shrinkWrap: true,
                            itemCount: options.length,
                            itemBuilder: (BuildContext context, int index) {
                              final option = options.elementAt(index);
                              return InkWell(
                                onTap: () => onSelected(option),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        option['client_name']?.toString() ?? '',
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black87,
                                        ),
                                      ),
                                      if (option['client_place'] != null &&
                                          option['client_place']
                                              .toString()
                                              .isNotEmpty)
                                        Text(
                                          option['client_place'].toString(),
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[600],
                                          ),
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
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: "Client Name *",
                        prefixIcon: Icon(Icons.person),
                      ),
                      onChanged: (v) => _nameCtrl.text = v,
                      validator: (v) => v!.isEmpty ? "Required" : null,
                    );
                  },
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _phoneCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(labelText: "Phone"),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _placeCtrl,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(labelText: "Place"),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 25),

                _sectionHeader(
                  "1. Materials Input (Raw)",
                  icon: Icons.download,
                ),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    border: Border.all(color: Colors.orange.withOpacity(0.5)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      ..._materials.asMap().entries.map(
                        (entry) => _buildItemRow(entry.key, _materials, "Item"),
                      ),
                      TextButton.icon(
                        onPressed: _addMaterial,
                        icon: const Icon(Icons.add, color: Colors.deepOrange),
                        label: const Text(
                          "Add Item",
                          style: TextStyle(color: Colors.deepOrange),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                _sectionHeader(
                  "2. Products Output (To Make)",
                  icon: Icons.upload,
                ),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    border: Border.all(color: Colors.blue.withOpacity(0.5)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      ..._products.asMap().entries.map(
                        (entry) => _buildProductRow(entry.key),
                      ),
                      TextButton.icon(
                        onPressed: _addProduct,
                        icon: const Icon(Icons.add, color: Colors.blue),
                        label: const Text(
                          "Add Product",
                          style: TextStyle(color: Colors.blue),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 25),

                _sectionHeader("Details"),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _costCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: "Total Cost",
                          prefixText: "₹ ",
                          suffixIcon: Icon(
                            Icons.auto_awesome,
                            size: 16,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _advanceCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: "Advance",
                          prefixText: "₹ ",
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _detailsCtrl,
                  maxLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: "Notes"),
                ),
                const SizedBox(height: 30),
                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1A237E),
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _save,
                    child: const Text(
                      "CREATE JOB",
                      style: TextStyle(
                        fontSize: 18,
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
    );
  }

  // --- AUTOCOMPLETE FOR MATERIALS ---
  Widget _buildItemRow(
    int index,
    List<Map<String, dynamic>> list,
    String label,
  ) {
    int totalQty = list[index]['qty'];
    int remaining = _getRemainingQty(list[index]['id'], totalQty);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Autocomplete<String>(
              optionsBuilder: (v) => v.text.isEmpty
                  ? const Iterable.empty()
                  : _knownItems.where(
                      (o) => o.toLowerCase().contains(v.text.toLowerCase()),
                    ),
              onSelected: (s) => setState(() => list[index]['name'] = s),
              optionsViewBuilder: (context, onSelected, options) {
                return Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    elevation: 6,
                    color: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.grey.shade200),
                    ),
                    child: Container(
                      width: 280,
                      constraints: const BoxConstraints(maxHeight: 220),
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        shrinkWrap: true,
                        itemCount: options.length,
                        itemBuilder: (BuildContext context, int index) {
                          final String option = options.elementAt(index);
                          return InkWell(
                            onTap: () => onSelected(option),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              child: Text(
                                option,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
              fieldViewBuilder: (ctx, ctrl, focus, submit) {
                if (ctrl.text != list[index]['name']) {
                  ctrl.text = list[index]['name'];
                }
                return TextFormField(
                  controller: ctrl,
                  focusNode: focus,
                  textCapitalization: TextCapitalization.words,
                  decoration: _fieldDec("$label Name"),
                  onChanged: (v) => list[index]['name'] = v,
                );
              },
            ),
          ),
          const SizedBox(width: 8),

          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  initialValue: totalQty == 0 ? null : totalQty.toString(),
                  keyboardType: TextInputType.number,
                  decoration: _fieldDec("Qty"),
                  onChanged: (v) =>
                      setState(() => list[index]['qty'] = int.tryParse(v) ?? 0),
                ),
                if (totalQty > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, left: 4),
                    child: Text(
                      "Rem: $remaining",
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: remaining < 0
                            ? Colors.red
                            : (remaining == 0
                                  ? Colors.green
                                  : Colors.orange[800]),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          if (list.length > 1)
            IconButton(
              icon: const Icon(Icons.remove_circle, color: Colors.red),
              onPressed: () => setState(() {
                String delId = list[index]['id'];
                for (var out in _products) {
                  List links = out['linked_materials'] ?? [];
                  links.removeWhere((l) => l['id'] == delId);
                }
                list.removeAt(index);
              }),
            ),
        ],
      ),
    );
  }

  // --- AUTOCOMPLETE WITH PRICE AUTO-FILL FOR PRODUCTS ---
  Widget _buildProductRow(int index) {
    final List links = _products[index]['linked_materials'] ?? [];
    final linkedCount = links.length;
    final isLinked = linkedCount > 0;

    // --- CALCULATE ROW TOTAL ---
    int qty = _products[index]['qty'] ?? 0;
    double rate = _products[index]['rate'] ?? 0.0;
    double rowTotal = qty * rate;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                flex: 4,
                child: Autocomplete<String>(
                  optionsBuilder: (v) => v.text.isEmpty
                      ? const Iterable.empty()
                      : _knownItems.where(
                          (o) => o.toLowerCase().contains(v.text.toLowerCase()),
                        ),
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
                    return Align(
                      alignment: Alignment.topLeft,
                      child: Material(
                        elevation: 6,
                        color: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Colors.grey.shade200),
                        ),
                        child: Container(
                          width: 280,
                          constraints: const BoxConstraints(maxHeight: 220),
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            shrinkWrap: true,
                            itemCount: options.length,
                            itemBuilder: (BuildContext context, int index) {
                              final String option = options.elementAt(index);
                              return InkWell(
                                onTap: () => onSelected(option),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  child: Text(
                                    option,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    );
                  },
                  fieldViewBuilder: (ctx, ctrl, focus, submit) {
                    if (ctrl.text != _products[index]['name']) {
                      ctrl.text = _products[index]['name'];
                    }
                    return TextFormField(
                      controller: ctrl,
                      focusNode: focus,
                      textCapitalization: TextCapitalization.words,
                      decoration: _fieldDec("Product Name"),
                      onChanged: (v) {
                        _products[index]['name'] = v;
                        final trimmed = v.trim();
                        final matchedKey = _historicalRates.keys.firstWhere(
                          (k) => k.toLowerCase() == trimmed.toLowerCase(),
                          orElse: () => "",
                        );
                        if (matchedKey.isNotEmpty) {
                          setState(() {
                            _products[index]['rate'] = _historicalRates[matchedKey];
                            _calculateTotal();
                          });
                        }
                      },
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
              // Qty
              Expanded(
                flex: 2,
                child: TextFormField(
                  initialValue: _products[index]['qty'] == 0
                      ? null
                      : _products[index]['qty'].toString(),
                  keyboardType: TextInputType.number,
                  decoration: _fieldDec("Qty"),
                  onChanged: (v) {
                    // Update state so the rowTotal instantly recalcs
                    setState(() {
                      _products[index]['qty'] = int.tryParse(v) ?? 0;
                      _calculateTotal();
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              // Rate
              Expanded(
                flex: 2,
                child: TextFormField(
                  key: ValueKey(
                    "rate_${_products[index]['id']}_${_products[index]['name']}",
                  ),
                  initialValue: _products[index]['rate'] == 0.0
                      ? null
                      : _products[index]['rate'].toString(),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: _fieldDec("Rate"),
                  onChanged: (v) {
                    // Update state so the rowTotal instantly recalcs
                    setState(() {
                      _products[index]['rate'] = double.tryParse(v) ?? 0.0;
                      _calculateTotal();
                    });
                  },
                ),
              ),
              if (_products.length > 1)
                IconButton(
                  icon: const Icon(Icons.remove_circle, color: Colors.red),
                  onPressed: () => setState(() {
                    _products.removeAt(index);
                    _calculateTotal();
                  }),
                ),
            ],
          ),

          // --- ROW TOTAL & LINKING BUTTON ---
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Link Button
                InkWell(
                  onTap: () => _openLinkDialog(index),
                  child: Row(
                    children: [
                      Transform.rotate(
                        angle: 1.57,
                        child: Icon(
                          Icons.link,
                          size: 16,
                          color: isLinked
                              ? const Color(0xFF1A237E)
                              : Colors.grey,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isLinked
                            ? "Uses $linkedCount materials"
                            : "Link Materials...",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isLinked
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: isLinked
                              ? const Color(0xFF1A237E)
                              : Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),

                // Item Total
                if (rowTotal > 0)
                  Text(
                    "= ₹${rowTotal.toStringAsFixed(0)}",
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: Colors.green[700],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _fieldDec(String label) => InputDecoration(
    labelText: label,
    fillColor: Colors.white,
    filled: true,
    isDense: true,
    contentPadding: const EdgeInsets.all(12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide.none,
    ),
  );

  Widget _sectionHeader(String title, {IconData? icon}) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 20, color: Colors.grey[700]),
          const SizedBox(width: 8),
        ],
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.grey[700],
          ),
        ),
      ],
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
    if (mounted) Navigator.pop(context);
  }
}
