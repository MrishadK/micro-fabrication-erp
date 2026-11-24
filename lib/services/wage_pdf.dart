import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';

class WagePdfService {
  static Future<Uint8List> generatePayslip({
    required String workerName,
    required String periodLabel,
    required double totalEarned,
    required double totalPaid,
    required int daysWorked,
    required int absentDays,
    required double normalHours,
    required double otHours,
    required double pieces,
    required int tasks,
    required List<Map<String, String>> dailyRecords,
  }) async {
    final pdf = pw.Document();

    final currency = NumberFormat.currency(
      locale: 'en_IN',
      symbol: 'Rs. ',
      decimalDigits: 0,
    );

    // 🔥 STRICTLY PERIOD BALANCE (Ignores All-Time Debt) 🔥
    double periodBalance = totalEarned - totalPaid;
    String statusLabel;
    PdfColor statusColor;
    PdfColor statusBgColor;

    if (periodBalance < 0) {
      statusLabel = "ADVANCE TAKEN: ${currency.format(periodBalance.abs())}";
      statusColor = PdfColors.orange800;
      statusBgColor = const PdfColor.fromInt(0xFFFFF3E0); // Orange 50
    } else if (periodBalance > 0) {
      statusLabel = "PENDING TO PAY: ${currency.format(periodBalance)}";
      statusColor = PdfColors.red700;
      statusBgColor = const PdfColor.fromInt(0xFFFFEBEE); // Red 50
    } else {
      statusLabel = "FULLY SETTLED";
      statusColor = PdfColors.green700;
      statusBgColor = const PdfColor.fromInt(0xFFE8F5E9); // Green 50
    }

    // Dynamic Summary Rows
    List<pw.Widget> summaryRows = [];
    if (normalHours > 0) {
      summaryRows.add(
        _buildTableRow(
          "Normal Hours Logged",
          "${normalHours.toStringAsFixed(1)} Hrs",
          isGrey: summaryRows.length % 2 != 0,
        ),
      );
    }
    if (otHours > 0) {
      summaryRows.add(
        _buildTableRow(
          "Overtime Logged",
          "${otHours.toStringAsFixed(1)} Hrs",
          isGrey: summaryRows.length % 2 != 0,
        ),
      );
    }
    if (pieces > 0) {
      summaryRows.add(
        _buildTableRow(
          "Total Standard Pieces",
          "${pieces.toInt()} Pcs",
          isGrey: summaryRows.length % 2 != 0,
        ),
      );
    }
    if (tasks > 0) {
      summaryRows.add(
        _buildTableRow(
          "Specific Jobs Completed",
          "$tasks Tasks",
          isGrey: summaryRows.length % 2 != 0,
        ),
      );
    }

    // 🔥 CHANGED TO MultiPage TO PREVENT CROPPING LONG TABLES 🔥
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        // 🔥 MULTI-PAGE FOOTER WITH PAGE NUMBERS 🔥
        footer: (pw.Context context) {
          return pw.Column(
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              pw.Divider(color: PdfColors.grey300),
              pw.SizedBox(height: 10),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    "This is a system generated payslip.",
                    style: const pw.TextStyle(
                      fontSize: 10,
                      color: PdfColors.grey500,
                    ),
                  ),
                  pw.Text(
                    "Page ${context.pageNumber} of ${context.pagesCount}",
                    style: const pw.TextStyle(
                      fontSize: 10,
                      color: PdfColors.grey500,
                    ),
                  ),
                ],
              ),
            ],
          );
        },
        build: (pw.Context context) {
          return [
            // --- HEADER ---
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      "PAYSLIP",
                      style: pw.TextStyle(
                        fontSize: 28,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.indigo900,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      "Generated on: ${DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now())}",
                      style: const pw.TextStyle(
                        fontSize: 10,
                        color: PdfColors.grey600,
                      ),
                    ),
                  ],
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: pw.BoxDecoration(
                    color: const PdfColor.fromInt(0xFFE8EAF6),
                    borderRadius: pw.BorderRadius.circular(8),
                    border: pw.Border.all(color: PdfColors.indigo200),
                  ),
                  child: pw.Text(
                    periodLabel,
                    style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.indigo900,
                    ),
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 25),

            // --- WORKER SUMMARY (DAYS WORKED / LEAVES) ---
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(15),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        "Worker Name",
                        style: const pw.TextStyle(
                          fontSize: 10,
                          color: PdfColors.grey700,
                        ),
                      ),
                      pw.Text(
                        workerName.toUpperCase(),
                        style: pw.TextStyle(
                          fontSize: 16,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  pw.Row(
                    children: [
                      _buildSummaryBox(
                        "Days Worked",
                        "$daysWorked",
                        PdfColors.green700,
                        const PdfColor.fromInt(0xFFE8F5E9),
                      ),
                      pw.SizedBox(width: 10),
                      _buildSummaryBox(
                        "Leaves",
                        "$absentDays",
                        PdfColors.red700,
                        const PdfColor.fromInt(0xFFFFEBEE),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 20),

            // --- PERIOD WORK SUMMARY (PIECES & HOURS) ---
            if (summaryRows.isNotEmpty) ...[
              pw.Text(
                "PERIOD WORK SUMMARY",
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.grey600,
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Container(
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey300),
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Column(children: summaryRows),
              ),
              pw.SizedBox(height: 20),
            ],

            // --- DETAILED DAILY BREAKDOWN TABLE ---
            pw.Text(
              "DETAILED DAILY LOG",
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.grey600,
              ),
            ),
            pw.SizedBox(height: 6),
            if (dailyRecords.isEmpty)
              pw.Container(
                padding: const pw.EdgeInsets.all(20),
                alignment: pw.Alignment.center,
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey300),
                ),
                child: pw.Text(
                  "No work logged in this period.",
                  style: const pw.TextStyle(color: PdfColors.grey600),
                ),
              )
            else
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300),
                columnWidths: {
                  0: const pw.FlexColumnWidth(1.8), // Date
                  1: const pw.FlexColumnWidth(3.5), // Task Name
                  2: const pw.FlexColumnWidth(2.5), // Qty & Rate
                  3: const pw.FlexColumnWidth(2.0), // Amount
                },
                children: [
                  // Table Header
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(
                      color: PdfColor.fromInt(0xFFE8EAF6),
                    ),
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(
                          "Date",
                          style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 10,
                          ),
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(
                          "Task / Work",
                          style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 10,
                          ),
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(
                          "Qty & Rate",
                          style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 10,
                          ),
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(
                          "Earned",
                          style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 10,
                          ),
                          textAlign: pw.TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                  // Table Rows
                  ...dailyRecords.map(
                    (row) => pw.TableRow(
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text(
                            row['date'] ?? '',
                            style: const pw.TextStyle(fontSize: 10),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text(
                            row['work'] ?? '',
                            style: const pw.TextStyle(fontSize: 10),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text(
                            row['qty_rate'] ?? '',
                            style: const pw.TextStyle(
                              fontSize: 10,
                              color: PdfColors.grey800,
                            ),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text(
                            "Rs. ${row['earned']}",
                            textAlign: pw.TextAlign.right,
                            style: pw.TextStyle(
                              fontSize: 10,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            pw.SizedBox(height: 25),

            // --- PERIOD SETTLEMENT SUMMARY ---
            // Using a Wrap to keep it together so it doesn't break awkwardly across pages
            pw.Wrap(
              children: [
                pw.Container(
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey300),
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Column(
                    children: [
                      _buildTableRow(
                        "Total Earned (This Period)",
                        currency.format(totalEarned),
                      ),
                      _buildTableRow(
                        "Total Paid (This Period)",
                        currency.format(totalPaid),
                        isGrey: true,
                      ),

                      // Final Calculation Box
                      pw.Container(
                        padding: const pw.EdgeInsets.all(16),
                        decoration: pw.BoxDecoration(
                          color: statusBgColor,
                          borderRadius: const pw.BorderRadius.vertical(
                            bottom: pw.Radius.circular(7),
                          ),
                        ),
                        child: pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text(
                              "PERIOD SETTLEMENT",
                              style: pw.TextStyle(
                                fontSize: 12,
                                fontWeight: pw.FontWeight.bold,
                                color: statusColor,
                              ),
                            ),
                            pw.Text(
                              statusLabel,
                              style: pw.TextStyle(
                                fontSize: 14,
                                fontWeight: pw.FontWeight.bold,
                                color: statusColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ]; // End of List of Widgets
        },
      ),
    );

    return pdf.save();
  }

  static pw.Widget _buildSummaryBox(
    String label,
    String value,
    PdfColor color,
    PdfColor bgColor,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: pw.BoxDecoration(
        color: bgColor,
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(color: color),
      ),
      child: pw.Column(
        children: [
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
              color: color,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(label, style: pw.TextStyle(fontSize: 9, color: color)),
        ],
      ),
    );
  }

  static pw.Widget _buildTableRow(
    String label,
    String value, {
    bool isGrey = false,
  }) {
    return pw.Container(
      color: isGrey ? PdfColors.grey100 : PdfColors.white,
      padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 11)),
          pw.Text(
            value,
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
