import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import '../database_helper.dart';

class PdfService {
  String _cleanPhone(dynamic raw) {
    if (raw == null) return "-";
    String s = raw.toString().trim();
    if (s.endsWith('.0')) {
      return s.substring(0, s.length - 2);
    }
    return s.isEmpty ? "-" : s;
  }

  double _getPlaceFontSize(dynamic raw) {
    if (raw == null) return 11;
    String text = raw.toString().trim();
    if (text.isEmpty) return 11;
    int len = text.length;
    if (len < 15) return 11;
    if (len < 25) return 9;
    return 7;
  }

  Future<Uint8List> buildReceipt(
    Map<String, dynamic> job, {
    bool isDetailed = true,
  }) async {
    final pdf = pw.Document();

    final font = pw.Font.helvetica();
    final fontBold = pw.Font.helveticaBold();

    pw.MemoryImage? logoImage;
    try {
      final ByteData data = await rootBundle.load('assets/bill.png');
      logoImage = pw.MemoryImage(data.buffer.asUint8List());
    } catch (e) {
      print("Could not load logo.png: $e");
    }

    final date = DateFormat(
      'dd/MM/yyyy',
    ).format(DateTime.parse(job['created_at'] ?? DateTime.now().toIso8601String()));

    String receiptNo =
        (job['bill_no'] != null && job['bill_no'].toString().trim().isNotEmpty)
        ? job['bill_no'].toString()
        : (job['id']?.toString() ?? '1');

    String cleanedPhone = _cleanPhone(job['client_phone']);

    Map<String, dynamic> itemsData = {};
    try {
      itemsData = jsonDecode(job['items'] ?? "{}");
    } catch (e) {
      itemsData = {};
    }
    final List<dynamic> inList = itemsData['in'] ?? [];
    final List<dynamic> outList = itemsData['out'] ?? [];

    // --- Prepare Raw Material Widgets ---
    List<pw.Widget> inputDisplayWidgets = [];
    if (inList.isNotEmpty) {
      for (var mat in inList) {
        String matId = mat['id']?.toString() ?? '';
        String name = mat['name']?.toString() ?? '-';
        int totalQty = (mat['qty'] as num?)?.toInt() ?? 0;

        String rightText = "$totalQty";

        if (isDetailed) {
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
          int rem = totalQty - used;
          rightText = "$totalQty (Rem: $rem)";
        }

        inputDisplayWidgets.add(
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 2),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(name, style: pw.TextStyle(font: font, fontSize: 10)),
                pw.Text(
                  rightText,
                  style: pw.TextStyle(font: fontBold, fontSize: 10),
                ),
              ],
            ),
          ),
        );
      }
    } else if (job['material_brought'] != null &&
        job['material_brought'].toString().isNotEmpty) {
      inputDisplayWidgets.add(
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              job['material_brought'],
              style: pw.TextStyle(font: font, fontSize: 10),
            ),
            pw.Text(
              "${job['qty_given'] ?? 0}",
              style: pw.TextStyle(font: fontBold, fontSize: 10),
            ),
          ],
        ),
      );
    }

    // --- Prepare Payment Data ---
    double totalAmt = (job['total_cost'] as num?)?.toDouble() ?? 0.0;
    double advanceAmt = (job['advance_paid'] as num?)?.toDouble() ?? 0.0;
    double scrapAmt = (job['scrap_value'] as num?)?.toDouble() ?? 0.0;
    double discountAmt = (job['discount'] as num?)?.toDouble() ?? 0.0;
    double normalPaid = (job['paid_sum'] as num?)?.toDouble() ?? 0.0;
    double balanceAmt = 0.0;

    if (isDetailed) {
      final db = await DatabaseHelper.instance.database;
      // 🔥 FIX 1: Added 'j.total_cost' to the query so the PDF catches live edits!
      final freshJobRes = await db.rawQuery(
        '''
        SELECT j.advance_paid, j.scrap_value, j.discount, j.total_cost,
               (SELECT COALESCE(SUM(amount), 0) FROM payments WHERE job_id = j.id) as paid_sum
        FROM jobs j
        WHERE j.id = ?
      ''',
        [job['id']],
      );

      if (freshJobRes.isNotEmpty) {
        final freshJob = freshJobRes.first;
        totalAmt = (freshJob['total_cost'] as num?)?.toDouble() ?? totalAmt;
        advanceAmt = (freshJob['advance_paid'] as num?)?.toDouble() ?? 0.0;
        normalPaid = (freshJob['paid_sum'] as num?)?.toDouble() ?? 0.0;
        scrapAmt = (freshJob['scrap_value'] as num?)?.toDouble() ?? 0.0;
        discountAmt = (freshJob['discount'] as num?)?.toDouble() ?? 0.0;
      }

      double totalReceived = advanceAmt + normalPaid;
      balanceAmt = totalAmt - (totalReceived + scrapAmt + discountAmt);
      // Allow negative balance to show as CREDIT (do NOT clamp to 0)
    }

    // Dynamically change header based on the payment status
    String headerTitle = "JOB CARD";
    if (isDetailed) {
      if (totalAmt <= 0) {
        headerTitle = "ESTIMATE";
      } else if (balanceAmt <= 0) {
        headerTitle = "CASH RECEIPT";
      } else {
        headerTitle = "ESTIMATE";
      }
    }

    // --- REACTIVE HEIGHT CALCULATION ---
    int maxItems = inList.length > outList.length
        ? inList.length
        : outList.length;
    // Each table row needs ~30px (text + vertical padding + spacing)
    double estimatedItemsHeight = maxItems * 30.0;
    // Table header row
    double tableHeaderHeight = 25.0;

    int instructionsLength = (job['work_details'] ?? "").toString().length;
    double estimatedInstructionsHeight =
        (instructionsLength / 40).ceil() * 15.0;

    // Payment summary box height (title + divider + rows + balance)
    double paymentSummaryHeight = isDetailed ? 140.0 : 0.0;

    // Base: header(50) + divider(10) + clientInfo(30) + spacing(30) + footer(70) + margins(60)
    double baseHeight = 250.0;

    double totalEstimatedHeight = baseHeight
        + estimatedItemsHeight
        + tableHeaderHeight
        + estimatedInstructionsHeight
        + paymentSummaryHeight
        + 50.0; // Safety buffer

    double finalPageHeight =
        totalEstimatedHeight > PdfPageFormat.a5.landscape.height
        ? totalEstimatedHeight
        : PdfPageFormat.a5.landscape.height;

    final dynamicPageFormat = PdfPageFormat.a5.landscape.copyWith(
      height: finalPageHeight,
    );

    pdf.addPage(
      pw.Page(
        pageFormat: dynamicPageFormat,
        margin: const pw.EdgeInsets.all(15),
        build: (pw.Context context) {
          return pw.Container(
            padding: const pw.EdgeInsets.all(15),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.black, width: 2),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // --- HEADER ---
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      headerTitle, // 🔥 FIX 3: Replaced the hardcoded condition
                      style: pw.TextStyle(font: fontBold, fontSize: 18),
                    ),
                    pw.Text(
                      "No: $receiptNo",
                      style: pw.TextStyle(
                        font: fontBold,
                        fontSize: 16,
                        color: PdfColors.red,
                      ),
                    ),
                  ],
                ),
                pw.Align(
                  alignment: pw.Alignment.topRight,
                  child: pw.Text(
                    "Date: $date",
                    style: pw.TextStyle(font: font, fontSize: 11),
                  ),
                ),
                pw.Divider(),
                pw.SizedBox(height: 5),

                // --- CLIENT INFO ---
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    _buildField("Name", job['client_name'], font, width: 120),
                    _buildField(
                      "Place",
                      job['client_place'],
                      font,
                      width: 80,
                      fontSize: _getPlaceFontSize(job['client_place']),
                    ),
                    _buildField("Phone", cleanedPhone, font, width: 80),
                  ],
                ),
                pw.SizedBox(height: 15),

                // --- MAIN CONTENT (2 COLUMNS) ---
                pw.Expanded(
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      // ==========================================
                      // LEFT COLUMN: Raw Material + Instructions
                      // ==========================================
                      // ✅ FIX: Changed from pw.Expanded to pw.Container with a fixed width.
                      // This prevents the PDF engine from crushing the layout into a single vertical line!
                      pw.Container(
                        width: 220,
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            // 1. Raw Material Box
                            pw.Container(
                              width: double.infinity,
                              padding: const pw.EdgeInsets.all(6),
                              decoration: pw.BoxDecoration(
                                color: PdfColors.grey100,
                                border: pw.Border.all(color: PdfColors.grey400),
                              ),
                              child: pw.Column(
                                crossAxisAlignment: pw.CrossAxisAlignment.start,
                                children: [
                                  pw.Text(
                                    "RAW MATERIAL IN:",
                                    style: pw.TextStyle(
                                      font: fontBold,
                                      fontSize: 10,
                                    ),
                                  ),
                                  pw.Divider(
                                    color: PdfColors.grey400,
                                    height: 8,
                                  ),
                                  if (inputDisplayWidgets.isNotEmpty)
                                    ...inputDisplayWidgets
                                  else
                                    pw.Text(
                                      "-",
                                      style: pw.TextStyle(
                                        font: font,
                                        fontSize: 10,
                                      ),
                                    ),
                                ],
                              ),
                            ),

                            pw.SizedBox(height: 15),

                            // 2. Instructions Box
                            pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.Text(
                                  "Special Instructions / Notes:",
                                  style: pw.TextStyle(
                                    font: fontBold,
                                    fontSize: 11,
                                  ),
                                ),
                                pw.SizedBox(height: 4),
                                pw.Container(
                                  width: double.infinity,
                                  // ✅ FIX: Forces a minimum height so it never looks tiny/cramped!
                                  constraints: const pw.BoxConstraints(
                                    minHeight: 100,
                                  ),
                                  padding: const pw.EdgeInsets.all(8),
                                  decoration: pw.BoxDecoration(
                                    color: PdfColors.yellow50,
                                    border: pw.Border.all(
                                      color: PdfColors.grey500,
                                      style: pw.BorderStyle.dashed,
                                    ),
                                  ),
                                  child: pw.Text(
                                    (job['work_details'] != null &&
                                            job['work_details']
                                                .toString()
                                                .trim()
                                                .isNotEmpty)
                                        ? job['work_details'].toString()
                                        : "-",
                                    style: pw.TextStyle(
                                      font: font,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      pw.SizedBox(width: 15),

                      // ==========================================
                      // RIGHT COLUMN: Job Details (Table) + Payment
                      // ==========================================
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            // 1. Job Details / Products Table Box
                            pw.Container(
                              width: double.infinity,
                              decoration: pw.BoxDecoration(
                                border: pw.Border.all(color: PdfColors.black),
                              ),
                              child: pw.Column(
                                crossAxisAlignment: pw.CrossAxisAlignment.start,
                                children: [
                                  pw.Container(
                                    padding: const pw.EdgeInsets.all(4),
                                    color: PdfColors.grey200,
                                    width: double.infinity,
                                    child: pw.Text(
                                      "JOB DETAILS / PARTICULARS:",
                                      style: pw.TextStyle(
                                        font: fontBold,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ),
                                  pw.Padding(
                                    padding: const pw.EdgeInsets.all(6),
                                    child: _buildProfessionalTable(
                                      outList,
                                      job,
                                      font,
                                      fontBold,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Space between table and payment summary
                            pw.SizedBox(height: 15),

                            // 2. Professional Detailed Payment Box
                            if (isDetailed)
                              pw.Container(
                                width: double.infinity,
                                padding: const pw.EdgeInsets.all(8),
                                decoration: pw.BoxDecoration(
                                  color: PdfColors.grey100,
                                  border: pw.Border.all(
                                    color: PdfColors.black,
                                    width: 1.5,
                                  ),
                                ),
                                child: pw.Column(
                                  crossAxisAlignment:
                                      pw.CrossAxisAlignment.start,
                                  children: [
                                    pw.Text(
                                      "PAYMENT SUMMARY",
                                      style: pw.TextStyle(
                                        font: fontBold,
                                        fontSize: 10,
                                      ),
                                    ),
                                    pw.Divider(
                                      color: PdfColors.black,
                                      height: 10,
                                    ),
                                    _buildPayRow(
                                      "Sub Total / Gross:",
                                      totalAmt,
                                      font,
                                      isBold: true,
                                    ),
                                    if (advanceAmt > 0)
                                      _buildPayRow(
                                        "Advance Paid:",
                                        advanceAmt,
                                        font,
                                        isDeduction: true,
                                      ),
                                    if (normalPaid > 0)
                                      _buildPayRow(
                                        "Payments Received:",
                                        normalPaid,
                                        font,
                                        isDeduction: true,
                                      ),
                                    if (scrapAmt > 0)
                                      _buildPayRow(
                                        "Scrap Deducted:",
                                        scrapAmt,
                                        font,
                                        isDeduction: true,
                                      ),
                                    if (discountAmt > 0)
                                      _buildPayRow(
                                        "Discount Given:",
                                        discountAmt,
                                        font,
                                        isDeduction: true,
                                      ),
                                    pw.Divider(
                                      color: PdfColors.grey500,
                                      height: 10,
                                    ),
                                    balanceAmt < 0
                                        ? _buildPayRow(
                                            "CREDIT:",
                                            balanceAmt.abs(),
                                            fontBold,
                                            isBold: true,
                                            size: 12,
                                            isCredit: true,
                                          )
                                        : _buildPayRow(
                                            "BALANCE DUE:",
                                            balanceAmt,
                                            fontBold,
                                            isBold: true,
                                            size: 12,
                                          ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                pw.SizedBox(height: 10),
                pw.Divider(color: PdfColors.black, thickness: 1.5),

                // --- FOOTER ---
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    _buildContactRow("9447106475, 9495574595", font, logoImage),
                    pw.Column(
                      children: [
                        pw.SizedBox(height: 15),
                        pw.Container(
                          width: 120,
                          height: 1,
                          color: PdfColors.black,
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          "Authorized Signature",
                          style: pw.TextStyle(font: fontBold, fontSize: 10),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );

    return pdf.save();
  }

  Future<Uint8List> generateReceiptBytes(
    Map<String, dynamic> job, {
    bool isDetailed = true,
  }) async {
    return await buildReceipt(job, isDetailed: isDetailed);
  }

  // --- Professional Table Builder ---
  pw.Widget _buildProfessionalTable(
    List<dynamic> outList,
    Map<String, dynamic> job,
    pw.Font font,
    pw.Font fontBold,
  ) {
    if (outList.isEmpty) {
      if (job['product_type'] != null &&
          job['product_type'].toString().isNotEmpty) {
        return pw.Text(
          "${job['product_type']} - Qty: ${job['target_qty'] ?? 0}",
          style: pw.TextStyle(font: font, fontSize: 10),
        );
      }
      return pw.Text("-", style: pw.TextStyle(font: font, fontSize: 10));
    }

    return pw.Table(
      columnWidths: {
        0: const pw.FlexColumnWidth(3), // Item Name
        1: const pw.FlexColumnWidth(1), // Qty
        2: const pw.FlexColumnWidth(1.5), // Rate
        3: const pw.FlexColumnWidth(1.5), // Amount
      },
      children: [
        // Table Header
        pw.TableRow(
          decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey400)),
          ),
          children: [
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 4),
              child: pw.Text(
                "Item",
                style: pw.TextStyle(font: fontBold, fontSize: 9),
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 4),
              child: pw.Text(
                "Qty",
                style: pw.TextStyle(font: fontBold, fontSize: 9),
                textAlign: pw.TextAlign.center,
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 4),
              child: pw.Text(
                "Rate",
                style: pw.TextStyle(font: fontBold, fontSize: 9),
                textAlign: pw.TextAlign.right,
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 4),
              child: pw.Text(
                "Amount",
                style: pw.TextStyle(font: fontBold, fontSize: 9),
                textAlign: pw.TextAlign.right,
              ),
            ),
          ],
        ),
        // Table Rows
        ...outList.map((prod) {
          String name = prod['name']?.toString() ?? '-';
          int qty = (prod['qty'] as num?)?.toInt() ?? 0;

          double rate =
              (prod['price'] as num?)?.toDouble() ??
              (prod['rate'] as num?)?.toDouble() ??
              0.0;
          double amount = rate * qty;

          String rateStr = rate > 0 ? rate.toStringAsFixed(2) : "-";
          String amountStr = amount > 0 ? amount.toStringAsFixed(2) : "-";

          return pw.TableRow(
            children: [
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 3),
                child: pw.Text(
                  name,
                  style: pw.TextStyle(font: font, fontSize: 10),
                ),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 3),
                child: pw.Text(
                  "$qty",
                  style: pw.TextStyle(font: font, fontSize: 10),
                  textAlign: pw.TextAlign.center,
                ),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 3),
                child: pw.Text(
                  rateStr,
                  style: pw.TextStyle(font: font, fontSize: 10),
                  textAlign: pw.TextAlign.right,
                ),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 3),
                child: pw.Text(
                  amountStr,
                  style: pw.TextStyle(font: font, fontSize: 10),
                  textAlign: pw.TextAlign.right,
                ),
              ),
            ],
          );
        }).toList(),
      ],
    );
  }

  pw.Widget _buildPayRow(
    String label,
    double amount,
    pw.Font font, {
    bool isBold = false,
    bool isDeduction = false,
    bool isCredit = false,
    double size = 10,
  }) {
    String prefix = isDeduction ? "- Rs. " : "Rs. ";
    PdfColor textColor = PdfColors.black;
    if (isDeduction) textColor = PdfColors.red800;
    if (isCredit) textColor = PdfColors.green800;
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              font: isBold ? pw.Font.helveticaBold() : font,
              fontSize: size,
              color: textColor,
            ),
          ),
          pw.Text(
            "$prefix${amount.toStringAsFixed(2)}",
            style: pw.TextStyle(
              font: isBold ? pw.Font.helveticaBold() : font,
              fontSize: size,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildContactRow(
    String number,
    pw.Font font,
    pw.MemoryImage? logoImage,
  ) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        if (logoImage != null)
          pw.Image(logoImage, width: 35, height: 35)
        else
          pw.SizedBox(width: 35),
        pw.SizedBox(width: 8),
        pw.Text(
          number,
          style: pw.TextStyle(
            font: font,
            fontSize: 11,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ],
    );
  }

  pw.Widget _buildField(
    String label,
    dynamic rawValue,
    pw.Font font, {
    double width = 100,
    double? fontSize,
  }) {
    final String value = (rawValue == null || rawValue.toString().trim().isEmpty)
        ? "-"
        : rawValue.toString().trim();
    final double finalFontSize = fontSize ?? 11;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Container(
          height: 14,
          alignment: pw.Alignment.bottomLeft,
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                "$label: ",
                style: pw.TextStyle(font: font, fontSize: 11),
              ),
              pw.SizedBox(
                width: width,
                child: pw.Text(
                  value,
                  maxLines: 1,
                  overflow: pw.TextOverflow.clip,
                  style: pw.TextStyle(
                    font: font,
                    fontSize: finalFontSize,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 1),
        pw.Container(width: width + 30, height: 1, color: PdfColors.grey),
      ],
    );
  }
}
