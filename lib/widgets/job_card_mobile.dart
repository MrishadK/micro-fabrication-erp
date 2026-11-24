// ignore_for_file: unused_result

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:printing/printing.dart';
import '../providers.dart';
import '../database_helper.dart';
import '../services/pdf_service.dart';
import 'edit_job_dialog.dart';
import 'delivery_dialog.dart';
import 'payment_dialog.dart';

class JobCardMobile extends StatelessWidget {
  final Map<String, dynamic> job;
  final WidgetRef ref;
  final PdfService _pdf = PdfService();

  JobCardMobile({super.key, required this.job, required this.ref});

  Future<void> _deleteJob(BuildContext context) async {
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
      if (!context.mounted) return;
      await DatabaseHelper.instance.deleteJob(job['id']);
      ref.refresh(activeJobsProvider);
    }
  }

  // 🔥 STATUS PICKER BOTTOM SHEET WITH COLORS 🔥
  void _showStatusPicker(BuildContext context, String currentStatus) {
    HapticFeedback.lightImpact();
    final statuses = ['Nothing', 'Ongoing', 'Ready', 'Done'];

    Color getBgColor(String s) {
      if (s == 'Nothing') return Colors.grey[200]!;
      if (s == 'Ongoing') return Colors.orange[50]!;
      if (s == 'Ready') return Colors.blue[50]!;
      return Colors.green[50]!;
    }

    Color getTextColor(String s) {
      if (s == 'Nothing') return Colors.grey[700]!;
      if (s == 'Ongoing') return Colors.orange[800]!;
      if (s == 'Ready') return Colors.blue[700]!;
      return Colors.green[700]!;
    }

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Update Status",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              ...statuses.map((s) {
                final bgColor = getBgColor(s);
                final textColor = getTextColor(s);

                return ListTile(
                  leading: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: bgColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: textColor, width: 2),
                    ),
                  ),
                  title: Text(
                    s,
                    style: TextStyle(
                      fontWeight: s == currentStatus
                          ? FontWeight.bold
                          : FontWeight.w500,
                      color: s == currentStatus
                          ? Colors.black
                          : Colors.grey[800],
                    ),
                  ),
                  trailing: s == currentStatus
                      ? Icon(Icons.check_circle, color: textColor)
                      : null,
                  onTap: () async {
                    Navigator.pop(ctx);
                    if (s != currentStatus) {
                      final updatedJob = Map<String, dynamic>.from(job);
                      updatedJob['status'] = s;

                      if (s == 'Done') {
                        updatedJob['completed_at'] = DateTime.now()
                            .toIso8601String();
                      }

                      updatedJob.remove('delivered_sum');
                      updatedJob.remove('paid_sum');

                      await DatabaseHelper.instance.updateJob(updatedJob);
                      ref.refresh(activeJobsProvider);
                      ref.read(dbRefreshTriggerProvider.notifier).state++;
                    }
                  },
                );
              }).toList(),
            ],
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
    final sanitizedName = (job['client_name'] ?? 'Client').toString().replaceAll(
      RegExp(r'[^\w\s]+'),
      '',
    ).trim();
    final billNo = (job['bill_no'] != null && job['bill_no'].toString().trim().isNotEmpty)
        ? job['bill_no'].toString()
        : (job['id']?.toString() ?? '1');
    final String prefix = isDetailed ? "Estimate" : "JobCard";
    final String docName = "${prefix}_${billNo}_$sanitizedName";
    final String title = isDetailed
        ? "Bill Preview (#$billNo - ${job['client_name'] ?? 'Client'})"
        : "Job Card Preview (#$billNo - ${job['client_name'] ?? 'Client'})";

    showDialog(
      context: context,
      builder: (ctx) {
        final screenSize = MediaQuery.of(ctx).size;
        final dialogWidth = (screenSize.width * 0.9).clamp(320.0, 950.0);
        final dialogHeight = (screenSize.height * 0.9).clamp(400.0, 850.0);

        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          backgroundColor: Colors.white,
          clipBehavior: Clip.antiAlias,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: SizedBox(
            width: dialogWidth,
            height: dialogHeight,
            child: Column(
              children: [
                // Top Header Bar
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: const BoxDecoration(
                    color: Color(0xFF1E293B),
                  ),
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
                // In-App PDF Preview with built-in Print button and zoom controls
                Expanded(
                  child: PdfPreview(
                    build: (format) async => await _pdf.generateReceiptBytes(
                      job,
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
              ],
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
        job,
        isDetailed: isDetailed,
      );
      final sanitizedName = (job['client_name'] ?? 'Client').toString().replaceAll(
        RegExp(r'[^\w\s]+'),
        '',
      ).trim();
      final billNo = (job['bill_no'] != null && job['bill_no'].toString().trim().isNotEmpty)
          ? job['bill_no'].toString()
          : (job['id']?.toString() ?? '1');
      final String prefix = isDetailed ? "Estimate" : "JobCard";
      final String docName = "${prefix}_${billNo}_$sanitizedName";

      await Printing.sharePdf(
        bytes: pdfBytes,
        filename: '$docName.pdf',
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error sharing document: $e"),
            backgroundColor: Colors.red,
          ),
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
                  "Choose document format to print or share for ${job['client_name'] ?? 'Client'}:",
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
    final status = job['status'] ?? 'Nothing';
    final date = DateTime.parse(
      job['created_at'] ?? DateTime.now().toIso8601String(),
    );

    final double cost = (job['total_cost'] as num?)?.toDouble() ?? 0;
    final double advance = (job['advance_paid'] as num?)?.toDouble() ?? 0;
    final double paymentsSum = (job['paid_sum'] as num?)?.toDouble() ?? 0;
    final double totalReceived = advance + paymentsSum;
    final double discount = (job['discount'] as num?)?.toDouble() ?? 0;
    final double scrap = (job['scrap_value'] as num?)?.toDouble() ?? 0;

    final double bal = cost - totalReceived - discount - scrap;
    final double amountToPay = bal > 0 ? bal : 0;

    String balText;
    Color balColor;

    if (cost == 0) {
      balText = "ESTIMATE";
      balColor = Colors.orange[800]!;
    } else if (bal < 0) {
      balText = "CREDIT ₹${bal.abs().toStringAsFixed(0)}";
      balColor = Colors.blue[700]!;
    } else if (bal == 0) {
      balText = "FULLY PAID";
      balColor = Colors.green[700]!;
    } else {
      balText = "₹${bal.toStringAsFixed(0)}";
      balColor = Colors.red[800]!;
    }
    final bool showDueFormat = cost > 0 && bal > 0;

    Color statusBg;
    Color statusText;
    String statusLabel = status.toUpperCase();

    if (status == 'Nothing') {
      statusBg = Colors.grey[200]!;
      statusText = Colors.grey[700]!;
    } else if (status == 'Ongoing') {
      statusBg = Colors.orange[50]!;
      statusText = Colors.orange[800]!;
    } else if (status == 'Ready') {
      statusBg = Colors.blue[50]!;
      statusText = Colors.blue[700]!;
    } else {
      statusBg = Colors.green[50]!;
      statusText = Colors.green[700]!;
    }

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

    final int targetQty = (job['target_qty'] as int?) ?? 0;
    final int deliveredQty = (job['delivered_sum'] as int?) ?? 0;
    final double progress = targetQty > 0
        ? (deliveredQty / targetQty).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
          BoxShadow(
            color: Colors.indigo.withOpacity(0.02),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => HapticFeedback.lightImpact(),
            child: Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,

                // --- HEADER ---
                title: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(width: 6, color: statusText),

                      // 🔥 MIDDLE COLUMN (Dedicated entirely to Name and Work Info) 🔥
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                job['client_name'] ?? "Unknown",
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF263238),
                                ),
                                maxLines: 2, // Allows name to wrap safely
                                overflow: TextOverflow.ellipsis,
                              ),

                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildStatBlock(
                                      label: "INPUTS",
                                      count: materials.length,
                                      name: materials.isNotEmpty
                                          ? materials[0]['name']
                                          : "-",
                                      icon: Icons.download_rounded,
                                      color: Colors.orange,
                                    ),
                                  ),
                                  Container(
                                    width: 1,
                                    height: 30,
                                    color: Colors.grey[200],
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                    ),
                                  ),
                                  Expanded(
                                    child: _buildStatBlock(
                                      label: "OUTPUTS",
                                      count: products.length,
                                      name: products.isNotEmpty
                                          ? products[0]['name']
                                          : "-",
                                      icon: Icons.upload_rounded,
                                      color: Colors.blue,
                                    ),
                                  ),
                                ],
                              ),

                              Container(
                                margin: const EdgeInsets.only(top: 8),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: remainingMats.isEmpty
                                      ? Colors.green.withOpacity(.4)
                                      : Colors.orange.withOpacity(.4),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      remainingMats.isEmpty
                                          ? Icons.check_circle_outline
                                          : Icons.inventory_2_outlined,
                                      size: 12,
                                      color: Colors.black,
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
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

                              const SizedBox(height: 12),
                              if (status != 'Done' && targetQty > 0)
                                Column(
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          "Dispatch Progress",
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.grey[500],
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        Text(
                                          "$deliveredQty / $targetQty",
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.blue[800],
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(2),
                                      child: LinearProgressIndicator(
                                        value: progress,
                                        minHeight: 4,
                                        backgroundColor: Colors.grey[200],
                                        valueColor:
                                            const AlwaysStoppedAnimation(
                                              Colors.blue,
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),

                      // 🔥 RIGHT-MOST COLUMN (Balance, Status, Bill No, Date) 🔥
                      Padding(
                        padding: const EdgeInsets.only(
                          right: 14,
                          top: 12,
                          bottom: 12,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            if (showDueFormat) ...[
                              Text(
                                balText,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  color: balColor,
                                ),
                              ),
                              Text(
                                "/ ₹${cost.toStringAsFixed(0)}",
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[500],
                                ),
                              ),
                            ] else
                              Text(
                                balText,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  color: balColor,
                                ),
                              ),
                            const SizedBox(height: 8),

                            // Status Badge
                            Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () => _showStatusPicker(context, status),
                                borderRadius: BorderRadius.circular(4),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: statusBg,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: statusText.withOpacity(0.4),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        statusLabel,
                                        style: const TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black,
                                        ),
                                      ),
                                      const SizedBox(width: 2),
                                      Icon(
                                        Icons.arrow_drop_down,
                                        size: 14,
                                        color: statusText,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),

                            // Bill Badge
                            if (job['bill_no'] != null &&
                                job['bill_no']
                                    .toString()
                                    .trim()
                                    .isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.grey[100],
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: Colors.grey.shade300,
                                  ),
                                ),
                                child: Text(
                                  "Bill #${job['bill_no']}",
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey[700],
                                  ),
                                ),
                              ),
                            ],

                            const SizedBox(height: 10),

                            // Clean single-line Date
                            Text(
                              DateFormat('dd MMM yyyy').format(date),
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey[500],
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // --- EXPANDED DETAILS ---
                children: [
                  const Divider(height: 1, color: Colors.grey),
                  Container(
                    color: const Color(0xFFF9FAFB),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "PRODUCTION FLOW",
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 10),
                        ..._buildLinkedItems(materials, products),
                        const SizedBox(height: 15),
                        if (job['work_details'] != null &&
                            job['work_details'].toString().isNotEmpty) ...[
                          const Text(
                            "NOTES:",
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            job['work_details'],
                            style: const TextStyle(fontSize: 13),
                          ),
                          const SizedBox(height: 20),
                        ],

                        // Actions
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              if (amountToPay > 0) ...[
                                _ActionButton(
                                  icon: Icons.payments_outlined,
                                  label: "Pay",
                                  color: Colors.green[800]!,
                                  onTap: () => showDialog(
                                    context: context,
                                    builder: (c) =>
                                        PaymentDialog(job: job, ref: ref),
                                  ),
                                ),
                                const SizedBox(width: 10),
                              ],
                              _ActionButton(
                                icon: Icons.print_rounded,
                                label: "Print / Share",
                                color: const Color(0xFF4F46E5),
                                onTap: () => _printOrShareBill(context),
                              ),
                              const SizedBox(width: 10),
                              _ActionButton(
                                icon: Icons.edit,
                                label: "Edit",
                                color: Colors.blue,
                                onTap: () async {
                                  await showDialog(
                                    context: context,
                                    builder: (c) => EditJobDialog(job: job),
                                  );
                                  ref.refresh(activeJobsProvider);
                                },
                              ),
                              const SizedBox(width: 10),
                              _ActionButton(
                                icon: Icons.delete_outline,
                                label: "Delete",
                                color: Colors.red,
                                onTap: () => _deleteJob(context),
                              ),
                              const SizedBox(width: 10),
                              _ActionButton(
                                icon: Icons.phone_in_talk_rounded,
                                label: "Call",
                                color: const Color(0xFF16A34A),
                                onTap: () => _showCallDialog(context),
                              ),
                              const SizedBox(width: 20),
                              if (status != 'Done')
                                ElevatedButton.icon(
                                  onPressed: () {
                                    showDialog(
                                      context: context,
                                      builder: (context) =>
                                          DeliveryDialog(job: job, ref: ref),
                                    );
                                  },
                                  icon: const Icon(
                                    Icons.local_shipping,
                                    size: 16,
                                  ),
                                  label: const Text("DISPATCH"),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF1A237E),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    textStyle: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
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
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildLinkedItems(List<dynamic> inList, List<dynamic> outList) {
    List<Widget> widgets = [];
    Map<String, dynamic> inputMap = {};
    for (var item in inList) {
      if (item['id'] != null) inputMap[item['id']] = item;
    }
    Set<String> usedInputIds = {};

    for (var prod in outList) {
      List<dynamic> links = prod['linked_materials'] ?? [];
      if (links.isEmpty && prod['linked_ids'] != null) {
        links = (prod['linked_ids'] as List)
            .map((id) => {'id': id, 'used_qty': 1})
            .toList();
      }

      List<dynamic> myMaterials = [];
      for (var link in links) {
        String linkId = link['id'];
        if (inputMap.containsKey(linkId)) {
          var matDetail = Map<String, dynamic>.from(inputMap[linkId]);
          matDetail['used_qty'] = link['used_qty'] ?? 1;
          myMaterials.add(matDetail);
          usedInputIds.add(linkId);
        }
      }

      if (myMaterials.isEmpty) {
        myMaterials = inList
            .where((m) => m['linked_to'] == prod['name'])
            .map((m) => {...m, 'used_qty': m['qty']})
            .toList();
        for (var m in myMaterials) {
          if (m['id'] != null) usedInputIds.add(m['id']);
        }
      }
      widgets.add(_buildProductTreeItem(prod, myMaterials));
    }

    List<dynamic> orphans = inList
        .where((m) => m['id'] == null || !usedInputIds.contains(m['id']))
        .toList();
    if (outList.isEmpty && inList.isNotEmpty) orphans = inList;

    if (orphans.isNotEmpty) {
      if (outList.isNotEmpty) widgets.add(const SizedBox(height: 12));
      widgets.add(
        const Text(
          "Unlinked Materials",
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
      );
      widgets.add(const SizedBox(height: 4));
      for (var mat in orphans) widgets.add(_buildMaterialTile(mat));
    }
    return widgets.isEmpty
        ? [
            const Text(
              "No details available",
              style: TextStyle(color: Colors.grey),
            ),
          ]
        : widgets;
  }

  Widget _buildProductTreeItem(dynamic prod, List<dynamic> mats) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.withOpacity(0.1)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                const Icon(Icons.upload_rounded, size: 16, color: Colors.blue),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    prod['name'],
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Color(0xFF1565C0),
                    ),
                  ),
                ),
                Text(
                  "x${prod['qty']}",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          if (mats.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(height: 1),
                  const SizedBox(height: 4),
                  ...mats.map(
                    (m) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Transform.rotate(
                            angle: 1.57,
                            child: const Icon(
                              Icons.subdirectory_arrow_right,
                              size: 14,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              m['name'],
                              style: const TextStyle(
                                fontSize: 13,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                          Text(
                            "Uses x${m['used_qty']} (from ${m['qty']})",
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[700],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMaterialTile(dynamic mat) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.orange[50],
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          const Icon(Icons.download_rounded, size: 14, color: Colors.orange),
          const SizedBox(width: 8),
          Expanded(
            child: Text(mat['name'], style: const TextStyle(fontSize: 13)),
          ),
          Text(
            "x${mat['qty']}",
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildStatBlock({
    required String label,
    required int count,
    required String name,
    required IconData icon,
    required Color color,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 14, color: color),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "$count $label",
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                  letterSpacing: 0.5,
                ),
              ),
              Text(
                name,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
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
    final clientName = (job['client_name'] as String?)?.trim() ?? 'Client';
    final clientPlace = (job['client_place'] as String?)?.trim() ?? '';
    final phone = _cleanPhone(job['client_phone']);

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
                // Top header with icon and close button
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

                // Client Name
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

                // Client Place
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

                // BIG PHONE NUMBER Card
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
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
