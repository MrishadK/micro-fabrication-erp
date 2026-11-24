import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import '../database_helper.dart';
import 'dart:async';

class EditJobDialog extends StatefulWidget {
  final Map<String, dynamic> job;
  const EditJobDialog({super.key, required this.job});

  @override
  State<EditJobDialog> createState() => _EditJobDialogState();
}

class _EditJobDialogState extends State<EditJobDialog> {
  final _formKey = GlobalKey<FormState>();
  final Color primaryColor = const Color(0xFF1A237E);

  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  late TextEditingController _billNoCtrl;
  late TextEditingController _nameCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _placeCtrl;
  late TextEditingController _costCtrl;
  late TextEditingController _detailsCtrl;
  late TextEditingController _advanceCtrl;
  late TextEditingController _scrapCtrl;

  List<Map<String, dynamic>> _paymentHistory = [];

  List<Map<String, dynamic>> _inputItems = [];
  List<Map<String, dynamic>> _outputItems = [];

  List<String> _knownItems = [];
  Map<String, double> _historicalRates = {};

  DateTime? _deadline;
  String _status = "Ongoing";
  bool _isSaving = false;

  Timer? _snackBarDebounce;

  @override
  void initState() {
    super.initState();
    _loadSuggestions();

    _billNoCtrl = TextEditingController(
      text: widget.job['bill_no']?.toString(),
    );
    _nameCtrl = TextEditingController(text: widget.job['client_name']);
    _phoneCtrl = TextEditingController(text: widget.job['client_phone']);
    _placeCtrl = TextEditingController(
      text: widget.job['client_place']?.toString() ?? '',
    );
    _costCtrl = TextEditingController(
      text: widget.job['total_cost'].toString(),
    );
    _detailsCtrl = TextEditingController(text: widget.job['work_details']);

    if (widget.job['deadline_date'] != null) {
      _deadline = DateTime.tryParse(widget.job['deadline_date']);
    }

    String dbStatus = widget.job['status'] ?? "Ongoing";
    const validStatuses = ['Nothing', 'Ongoing', 'Ready', 'Done'];
    _status = validStatuses.contains(dbStatus) ? dbStatus : 'Ongoing';

    _advanceCtrl = TextEditingController(
      text: (widget.job['advance_paid'] ?? 0.0).toString(),
    );
    _scrapCtrl = TextEditingController(
      text: (widget.job['scrap_value'] ?? 0.0).toString(),
    );

    _parseItems(widget.job['items']);
    _loadFinancials();
  }

  Future<void> _loadFinancials() async {
    try {
      final db = await DatabaseHelper.instance.database;
      final payments = await db.query(
        'payments',
        where: 'job_id = ?',
        whereArgs: [widget.job['id']],
        orderBy: 'payment_date DESC',
      );
      if (mounted) {
        setState(() {
          _paymentHistory = payments;
        });
      }
    } catch (e) {
      debugPrint("Error loading payments: $e");
    }
  }

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

  String _generateId(String prefix) {
    return "${prefix}_${DateTime.now().microsecondsSinceEpoch}_${DateTime.now().microsecond}";
  }

  void _parseItems(String? jsonStr) {
    if (jsonStr == null || !jsonStr.startsWith('{')) {
      _inputItems.add({
        'id': _generateId('mat'),
        'name': widget.job['material_brought'] ?? '',
        'qty': widget.job['qty_given'] ?? 0,
      });
      _outputItems.add({
        'id': _generateId('prod'),
        'name': widget.job['product_type'] ?? '',
        'qty': widget.job['target_qty'] ?? 0,
        'rate': 0.0,
        'linked_materials': <Map<String, dynamic>>[],
      });
      return;
    }

    try {
      final data = jsonDecode(jsonStr);
      _inputItems = List<Map<String, dynamic>>.from(data['in'] ?? []);
      _outputItems = List<Map<String, dynamic>>.from(data['out'] ?? []);

      for (var item in _inputItems) {
        if (item['id'] == null) item['id'] = _generateId('mat');
      }

      for (var item in _outputItems) {
        if (item['id'] == null) item['id'] = _generateId('prod');
        if (item['rate'] == null) item['rate'] = 0.0;

        if (item['linked_ids'] != null && item['linked_materials'] == null) {
          item['linked_materials'] = [];
          for (String oldId in item['linked_ids']) {
            item['linked_materials'].add({'id': oldId, 'used_qty': 1});
          }
          item.remove('linked_ids');
        } else if (item['linked_materials'] == null) {
          item['linked_materials'] = <Map<String, dynamic>>[];
        } else {
          item['linked_materials'] = List<Map<String, dynamic>>.from(
            item['linked_materials'],
          );
        }
      }

      for (var mat in _inputItems) {
        if (mat.containsKey('linked_to') && mat['linked_to'] != null) {
          String targetName = mat['linked_to'];
          try {
            var targetProd = _outputItems.firstWhere(
              (p) => p['name'] == targetName,
            );
            List<Map<String, dynamic>> currentLinks =
                targetProd['linked_materials'];
            if (!currentLinks.any((l) => l['id'] == mat['id'])) {
              currentLinks.add({'id': mat['id'], 'used_qty': 1});
            }
          } catch (e) {
            // Ignore
          }
          mat.remove('linked_to');
        }
      }
    } catch (e) {
      debugPrint("Error parsing items: $e");
    }
  }

  void _calculateTotal() {
    double total = 0.0;
    for (var p in _outputItems) {
      int qty = p['qty'] ?? 0;
      double rate = p['rate'] ?? 0.0;
      total += (qty * rate);
    }
    _costCtrl.text = total.toInt().toString();
  }

  int _getRemainingQty(String matId, int totalQty) {
    int used = 0;
    for (var prod in _outputItems) {
      for (var link in (prod['linked_materials'] ?? [])) {
        if (link['id'] == matId) {
          used += (link['used_qty'] as int? ?? 0);
        }
      }
    }
    return totalQty - used;
  }

  // --- UPDATED TEXT-BOX LOGIC FOR LINKING ---
  void _openLinkDialog(int productIndex) {
    final validMaterials = _inputItems
        .where((m) => m['name'].toString().isNotEmpty)
        .toList();

    if (validMaterials.isEmpty) {
      if (_snackBarDebounce?.isActive ?? false) _snackBarDebounce!.cancel();
      _snackBarDebounce = Timer(const Duration(milliseconds: 300), () {
        _scaffoldMessengerKey.currentState?.clearSnackBars();
        _scaffoldMessengerKey.currentState?.showSnackBar(
          const SnackBar(
            content: Text("Add valid Input Materials first to link them."),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      });
      return;
    }

    showDialog(
      context: context,
      builder: (context) {
        List<Map<String, dynamic>> tempLinks = List<Map<String, dynamic>>.from(
          (_outputItems[productIndex]['linked_materials'] ?? []).map(
            (e) => Map<String, dynamic>.from(e),
          ),
        );

        // We use controllers to force the text to update if they type a number > maxAvailable
        Map<String, TextEditingController> textCtrls = {};
        for (var link in tempLinks) {
          textCtrls[link['id']] = TextEditingController(
            text: link['used_qty'].toString(),
          );
        }

        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text("Materials Used"),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: validMaterials.length,
                  itemBuilder: (ctx, i) {
                    final mat = validMaterials[i];
                    final String matId = mat['id'];
                    final int totalQty = mat['qty'] as int;

                    // Calculate how much of this material is used by OTHER products
                    int otherUsed = 0;
                    for (int p = 0; p < _outputItems.length; p++) {
                      if (p == productIndex) continue;
                      for (var link
                          in (_outputItems[p]['linked_materials'] ?? [])) {
                        if (link['id'] == matId)
                          otherUsed += (link['used_qty'] as int? ?? 0);
                      }
                    }
                    final int maxAvailable = totalQty - otherUsed;

                    int linkIndex = tempLinks.indexWhere(
                      (l) => l['id'] == matId,
                    );
                    bool isSelected = linkIndex != -1;

                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Checkbox(
                        value: isSelected,
                        activeColor: primaryColor,
                        // Prevent checking if no material is available
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
                              width: 65,
                              child: TextField(
                                controller: textCtrls[matId],
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                decoration: const InputDecoration(
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(
                                    vertical: 8,
                                    horizontal: 4,
                                  ),
                                  border: OutlineInputBorder(),
                                ),
                                onChanged: (val) {
                                  int parsed = int.tryParse(val) ?? 0;

                                  // --- CAP TO MAX AVAILABLE ---
                                  if (parsed > maxAvailable) {
                                    parsed = maxAvailable;
                                    textCtrls[matId]!.text = parsed.toString();
                                    // Move cursor to the end
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
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _outputItems[productIndex]['linked_materials'] =
                          tempLinks;
                    });
                    Navigator.pop(context);
                  },
                  child: const Text("Save"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _snackBarDebounce?.cancel();
    _billNoCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _placeCtrl.dispose();
    _costCtrl.dispose();
    _detailsCtrl.dispose();
    _advanceCtrl.dispose();
    _scrapCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 20),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 550,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.9,
          ),
          child: ScaffoldMessenger(
            key: _scaffoldMessengerKey,
            child: Scaffold(
              backgroundColor: Colors.transparent,
              body: Column(
                children: [
                  _buildHeader(),
                  Expanded(
                    child: Container(
                      color: Colors.white,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                        child: Form(
                          key: _formKey,
                          child: Column(
                            children: [
                              _buildSectionCard(
                                title: "Client Information",
                                icon: Icons.person_outline,
                                content: _buildClientInfo(),
                              ),
                              const SizedBox(height: 20),
                              _buildItemsEditor(),
                              const SizedBox(height: 20),
                              _buildSectionCard(
                                title: "Job Requirements",
                                icon: Icons.assignment_outlined,
                                content: _buildJobDetails(),
                              ),
                              const SizedBox(height: 20),
                              _buildSectionCard(
                                title: "Financial Ledger",
                                icon: Icons.account_balance_wallet_outlined,
                                content: _buildFinancialLedger(),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  _buildFooter(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildItemsEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          "1. Input Materials (Raw)",
          icon: Icons.download_rounded,
        ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: _boxDecoration(Colors.orange[50]!, Colors.orange),
          child: Column(
            children: [
              ..._inputItems.asMap().entries.map(
                (entry) => _buildMaterialRow(entry.key),
              ),
              _addButton(
                "Add Material",
                () => setState(
                  () => _inputItems.add({
                    'id': _generateId('mat'),
                    'name': '',
                    'qty': 0,
                  }),
                ),
                color: Colors.deepOrange,
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _sectionHeader(
          "2. Output Products (To Make)",
          icon: Icons.upload_rounded,
        ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: _boxDecoration(Colors.blue[50]!, Colors.blue),
          child: Column(
            children: [
              ..._outputItems.asMap().entries.map(
                (entry) => _buildProductRow(entry.key),
              ),
              _addButton(
                "Add Product",
                () => setState(
                  () => _outputItems.add({
                    'id': _generateId('prod'),
                    'name': '',
                    'qty': 0,
                    'rate': 0.0,
                    'linked_materials': <Map<String, dynamic>>[],
                  }),
                ),
                color: Colors.blue,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMaterialRow(int index) {
    int totalQty = _inputItems[index]['qty'];
    int remaining = _getRemainingQty(_inputItems[index]['id'], totalQty);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
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
              onSelected: (s) => setState(() => _inputItems[index]['name'] = s),
              optionsViewBuilder: (context, onSelected, options) {
                return Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    elevation: 6,
                    color: Colors.white,
                    clipBehavior: Clip.antiAlias,
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
                if (ctrl.text != _inputItems[index]['name']) {
                  ctrl.text = _inputItems[index]['name'];
                }
                return TextFormField(
                  controller: ctrl,
                  focusNode: focus,
                  decoration: _itemInputDec("Material Name", Colors.orange),
                  onChanged: (v) => _inputItems[index]['name'] = v,
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
                  decoration: _itemInputDec("Qty", Colors.transparent),
                  onChanged: (v) {
                    setState(() {
                      _inputItems[index]['qty'] = int.tryParse(v) ?? 0;
                    });
                  },
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
          IconButton(
            icon: Icon(Icons.remove_circle_outline, color: Colors.red[300]),
            onPressed: () => setState(() {
              String delId = _inputItems[index]['id'];
              for (var out in _outputItems) {
                List links = out['linked_materials'] ?? [];
                links.removeWhere((l) => l['id'] == delId);
              }
              _inputItems.removeAt(index);
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildProductRow(int index) {
    final List links = _outputItems[index]['linked_materials'] ?? [];
    final linkedCount = links.length;
    final isLinked = linkedCount > 0;

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
                      _outputItems[index]['name'] = s;
                      if (_historicalRates.containsKey(s)) {
                        _outputItems[index]['rate'] = _historicalRates[s];
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
                        clipBehavior: Clip.antiAlias,
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
                    if (ctrl.text != _outputItems[index]['name']) {
                      ctrl.text = _outputItems[index]['name'];
                    }
                    return TextFormField(
                      controller: ctrl,
                      focusNode: focus,
                      decoration: _itemInputDec("Product Name", Colors.blue),
                      onChanged: (v) => _outputItems[index]['name'] = v,
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextFormField(
                  initialValue: _outputItems[index]['qty'] == 0
                      ? null
                      : _outputItems[index]['qty'].toString(),
                  keyboardType: TextInputType.number,
                  decoration: _itemInputDec("Qty", Colors.transparent),
                  onChanged: (v) {
                    _outputItems[index]['qty'] = int.tryParse(v) ?? 0;
                    _calculateTotal();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextFormField(
                  key: ValueKey(
                    "rate_${_outputItems[index]['id']}_${_outputItems[index]['name']}",
                  ),
                  initialValue:
                      _outputItems[index]['rate'] == 0.0 ||
                          _outputItems[index]['rate'] == null
                      ? null
                      : _outputItems[index]['rate'].toString(),
                  keyboardType: TextInputType.number,
                  decoration: _itemInputDec("Rate", Colors.transparent),
                  onChanged: (v) {
                    _outputItems[index]['rate'] = double.tryParse(v) ?? 0.0;
                    _calculateTotal();
                  },
                ),
              ),
              IconButton(
                icon: Icon(Icons.remove_circle_outline, color: Colors.red[300]),
                onPressed: () => setState(() {
                  _outputItems.removeAt(index);
                  _calculateTotal();
                }),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: InkWell(
              onTap: () => _openLinkDialog(index),
              borderRadius: BorderRadius.circular(8),
              child: Row(
                children: [
                  Transform.rotate(
                    angle: 1.57,
                    child: Icon(
                      Icons.link,
                      size: 16,
                      color: isLinked ? primaryColor : Colors.grey,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isLinked
                          ? primaryColor.withOpacity(0.1)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isLinked
                            ? primaryColor
                            : Colors.grey.withOpacity(0.3),
                      ),
                    ),
                    child: Text(
                      isLinked
                          ? "Uses $linkedCount materials"
                          : "Link used materials...",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isLinked
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: isLinked ? primaryColor : Colors.grey[600],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(color: primaryColor),
      child: Row(
        children: [
          const Icon(Icons.edit_note, color: Colors.white, size: 28),
          const SizedBox(width: 12),
          Text(
            "Editing Bill #${widget.job['bill_no'] ?? widget.job['id']}",
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white70),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required Widget content,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: primaryColor),
              const SizedBox(width: 8),
              Text(
                title.toUpperCase(),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[700],
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          content,
        ],
      ),
    );
  }

  Widget _buildClientInfo() {
    return Column(
      children: [
        TextFormField(
          controller: _nameCtrl,
          decoration: _inputDec("Customer Name", Icons.person_rounded),
          validator: (v) => v!.isEmpty ? "Enter name" : null,
          textCapitalization: TextCapitalization.words,
        ),
        const SizedBox(height: 15),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _phoneCtrl,
                decoration: _inputDec(
                  "Phone Number",
                  Icons.phone_android_rounded,
                ),
                keyboardType: TextInputType.phone,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _placeCtrl,
                decoration: _inputDec(
                  "Place / Location",
                  Icons.location_on_rounded,
                ),
                textCapitalization: TextCapitalization.words,
              ),
            ),
          ],
        ),
        const SizedBox(height: 15),
        TextFormField(
          controller: _billNoCtrl,
          decoration: _inputDec("Bill Number", Icons.tag_rounded),
        ),
      ],
    );
  }

  Widget _buildJobDetails() {
    return Column(
      children: [
        TextFormField(
          controller: _costCtrl,
          decoration:
              _inputDec(
                "Estimated Total Cost (₹)",
                Icons.payments_outlined,
              ).copyWith(
                suffixIcon: const Icon(
                  Icons.auto_awesome,
                  size: 16,
                  color: Colors.grey,
                ),
              ),
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 15),
        TextFormField(
          controller: _detailsCtrl,
          decoration: _inputDec(
            "Work Instructions / Notes",
            Icons.notes_rounded,
          ),
          maxLines: 2,
        ),
        const SizedBox(height: 15),
        Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(8),
                child: InputDecorator(
                  decoration: _inputDec("Deadline Date", Icons.event),
                  child: Text(
                    _deadline == null
                        ? "Not Set"
                        : DateFormat('dd MMM yyyy').format(_deadline!),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _status,
                decoration: _inputDec("Status", Icons.analytics_outlined),
                items: ['Nothing', 'Ongoing', 'Ready', 'Done']
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: (val) => setState(() => _status = val!),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFinancialLedger() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _advanceCtrl,
                keyboardType: TextInputType.number,
                decoration: _inputDec("Advance Paid (₹)", Icons.payments_rounded),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _scrapCtrl,
                keyboardType: TextInputType.number,
                decoration: _inputDec("Scrap Deducted (₹)", Icons.recycling_rounded),
              ),
            ),
          ],
        ),
        if (_paymentHistory.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            "PAYMENT HISTORY",
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: Colors.green[50],
              border: Border.all(color: Colors.green[200]!),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: _paymentHistory.map((p) {
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.check_circle, color: Colors.green, size: 18),
                  title: Text(
                    "₹${p['amount']}",
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  subtitle: Text(
                    p['payment_date'] != null 
                      ? DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.parse(p['payment_date']))
                      : 'Unknown Date',
                    style: TextStyle(fontSize: 12, color: Colors.green[800]),
                  ),
                );
              }).toList(),
            ),
          ),
        ] else ...[
          const SizedBox(height: 20),
          Center(
            child: Text(
              "No additional payments recorded yet.",
              style: TextStyle(color: Colors.grey[500], fontStyle: FontStyle.italic, fontSize: 12),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey[200]!)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text("Discard"),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: _isSaving ? null : _saveChanges,
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            icon: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check_circle_outline, size: 20),
            label: Text(_isSaving ? "Saving..." : "Save Changes"),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDec(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 20, color: Colors.grey[600]),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      filled: true,
      fillColor: Colors.white,
    );
  }

  InputDecoration _itemInputDec(String hint, Color dotColor) {
    return InputDecoration(
      hintText: hint,
      isDense: true,
      contentPadding: const EdgeInsets.all(12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      prefixIcon: dotColor == Colors.transparent
          ? null
          : Icon(Icons.circle, size: 8, color: dotColor),
    );
  }

  BoxDecoration _boxDecoration(Color bg, Color border) {
    return BoxDecoration(
      color: bg,
      border: Border.all(color: border.withOpacity(0.5)),
      borderRadius: BorderRadius.circular(12),
    );
  }

  Widget _sectionHeader(String title, {IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey[700]),
          const SizedBox(width: 8),
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
  }

  Widget _addButton(String label, VoidCallback onTap, {required Color color}) =>
      TextButton.icon(
        onPressed: onTap,
        icon: Icon(Icons.add_circle_outline, size: 18, color: color),
        label: Text(label, style: TextStyle(color: color)),
      );

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _deadline ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (context, child) => Theme(
        data: Theme.of(
          context,
        ).copyWith(colorScheme: ColorScheme.light(primary: primaryColor)),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _deadline = picked);
  }

  Future<void> _saveChanges() async {
    HapticFeedback.lightImpact();
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      String itemsJson = jsonEncode({
        "in": _inputItems
            .where((e) => e['name'].toString().isNotEmpty)
            .toList(),
        "out": _outputItems
            .where((e) => e['name'].toString().isNotEmpty)
            .toList(),
      });

      String matSummary = _inputItems.isNotEmpty ? _inputItems[0]['name'] : "-";
      if (_inputItems.length > 1) matSummary += " +${_inputItems.length - 1}";

      String prodSummary = _outputItems.isNotEmpty
          ? _outputItems[0]['name']
          : "-";
      if (_outputItems.length > 1)
        prodSummary += " +${_outputItems.length - 1}";

      int targetQty = _outputItems.fold(
        0,
        (sum, item) => sum + (item['qty'] as int),
      );
      int givenQty = _inputItems.fold(
        0,
        (sum, item) => sum + (item['qty'] as int),
      );

      Map<String, dynamic> updatedJob = {
        'id': widget.job['id'],
        'bill_no': _billNoCtrl.text.trim(),
        'client_name': _nameCtrl.text.trim(),
        'client_place': _placeCtrl.text.trim(),
        'client_phone': _phoneCtrl.text.trim(),
        'items': itemsJson,
        'material_brought': matSummary,
        'qty_given': givenQty,
        'product_type': prodSummary,
        'target_qty': targetQty,
        'total_cost': double.tryParse(_costCtrl.text) ?? 0.0,
        'work_details': _detailsCtrl.text.trim(),
        'status': _status,
        'deadline_date': _deadline?.toIso8601String(),
        'advance_paid': double.tryParse(_advanceCtrl.text) ?? 0.0,
        'scrap_value': double.tryParse(_scrapCtrl.text) ?? 0.0,
      };

      await DatabaseHelper.instance.updateJob(updatedJob);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      _scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text("Save failed: $e"),
          behavior: SnackBarBehavior.floating,
        ),
      );
      setState(() => _isSaving = false);
    }
  }
}
