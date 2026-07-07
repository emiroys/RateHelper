import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import 'earnings_models.dart';
import 'l10n.dart';

/// Plain, printable earnings report intended for tax / ryczałt documentation.
///
/// Deliberately black-on-white and unstyled: this is a document an accountant
/// reads, not an app screen. Fonts are the app's bundled DM Sans TTFs so
/// Turkish (ş/ğ/ı) and Polish (ą/ł/ń) glyphs render correctly regardless of
/// the driver's chosen language — the standard PDF fonts cover neither.
class EarningsPdfExport {
  EarningsPdfExport._();

  /// The weeks belonging to the calendar month of [month] (only its year/month
  /// matter), using [aggregateByMonth]'s bucketing so the PDF's "this month" /
  /// "specific month" export can never drift from the on-screen monthly view.
  ///
  /// A week belongs to the month of its [WeekEarning.weekStart] (the Monday) —
  /// the app's single, established convention — so a week whose Monday lands
  /// exactly on the 1st is included, and a week straddling a month boundary
  /// counts entirely toward its start month. Returns an empty list when the
  /// month has no recorded weeks.
  static List<WeekEarning> weeksForMonth(
    List<WeekEarning> allWeeks,
    DateTime month,
  ) {
    for (final summary in aggregateByMonth(allWeeks)) {
      if (summary.month.year == month.year &&
          summary.month.month == month.month) {
        return summary.weeks;
      }
    }
    return const [];
  }

  /// Sanitizes [driverName] by stripping unsupported emojis and characters outside
  /// basic Latin and Latin Extended (which covers Polish and Turkish glyphs).
  static String sanitizeDriverName(String driverName) {
    final sanitized = driverName
        .replaceAll(RegExp(r'[^\x00-\xFF\u0100-\u017F\u0180-\u024F]'), '')
        .trim();
    return sanitized.isEmpty ? S.driverNameDefault : sanitized;
  }

  /// Builds the report for [weeks] (already filtered to the selected range and
  /// ordered oldest → newest is preferred) and hands it to the platform share
  /// sheet so the driver can send it to their accountant or save it.
  ///
  /// [rangeLabel] is the human-readable range (e.g. "Bu Ay") shown in the
  /// header. [driverName] is shown next to "Sürücü"; when blank the header
  /// falls back to [S.driverNameDefault] instead of leaving it empty.
  /// Returns silently if [weeks] is empty — callers guard that first.
  static Future<void> generateAndShare(
    List<WeekEarning> weeks, {
    required String rangeLabel,
    String driverName = '',
  }) async {
    if (weeks.isEmpty) return;

    final ordered = [...weeks]
      ..sort((a, b) => a.weekStart.compareTo(b.weekStart));

    final bytes = await _buildDocument(ordered, rangeLabel, driverName);

    final dir = await getTemporaryDirectory();
    // Sweep any leftovers from a previous export that was interrupted before its
    // own cleanup (crash / process kill) so financial PDFs never accumulate in
    // the cache dir. share_plus copies the file into its own scoped provider
    // cache before sharing, so our original is only needed for the copy step.
    await _cleanStaleReports(dir);

    final stamp = DateTime.now().millisecondsSinceEpoch;
    final file = File('${dir.path}/earnings_report_$stamp.pdf');
    await file.writeAsBytes(bytes, flush: true);

    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile(file.path,
                mimeType: 'application/pdf', name: 'earnings_report.pdf'),
          ],
          subject: S.pdfTitle,
          text: S.exportShareText,
        ),
      );
    } finally {
      // The copy share_plus made lives on until the next share; delete OUR
      // original immediately so the plaintext financial report doesn't linger
      // in a potentially world-readable cache on some OEM forks.
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {
          // Best-effort; the next export's sweep will catch it.
        }
      }
    }
  }

  /// Deletes any previously generated `earnings_report_*.pdf` files still sitting
  /// in [dir]. Best-effort: failures are swallowed so a locked/undeletable file
  /// can never block a fresh export.
  static Future<void> _cleanStaleReports(Directory dir) async {
    try {
      await for (final entity in dir.list()) {
        if (entity is File &&
            entity.uri.pathSegments.last.startsWith('earnings_report_') &&
            entity.path.endsWith('.pdf')) {
          try {
            await entity.delete();
          } catch (_) {
            // Ignore individual failures.
          }
        }
      }
    } catch (_) {
      // Directory listing can fail on odd filesystems; ignore.
    }
  }

  static Future<List<int>> _buildDocument(
    List<WeekEarning> weeks,
    String rangeLabel,
    String driverName,
  ) async {
    final regular = pw.Font.ttf(
      await rootBundle.load('assets/fonts/DMSans-Regular.ttf'),
    );
    final bold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/DMSans-Bold.ttf'),
    );

    final theme = pw.ThemeData.withFont(base: regular, bold: bold);
    final doc = pw.Document(theme: theme);

    var totalNetIncome = 0.0;
    var totalVat = 0.0;
    var totalNetProfit = 0.0;
    for (final w in weeks) {
      totalNetIncome += w.netIncome;
      totalVat += w.vat;
      totalNetProfit += w.netProfit;
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          _header(rangeLabel, driverName),
          pw.SizedBox(height: 20),
          _table(weeks),
          pw.SizedBox(height: 18),
          _summary(totalNetIncome, totalVat, totalNetProfit),
        ],
      ),
    );

    return doc.save();
  }

  static pw.Widget _header(String rangeLabel, String driverName) {
    final now = DateTime.now();
    final generated =
        '${_two(now.day)}.${_two(now.month)}.${now.year} ${_two(now.hour)}:${_two(now.minute)}';
    final displayName = sanitizeDriverName(driverName);
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          S.pdfTitle,
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 22),
        ),
        pw.SizedBox(height: 12),
        _headerLine('${S.pdfDriver}:', displayName),
        _headerLine('${S.pdfDateRange}:', rangeLabel),
        _headerLine('${S.pdfGeneratedOn}:', generated),
      ],
    );
  }

  static pw.Widget _headerLine(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 3),
      child: pw.Row(
        children: [
          pw.SizedBox(
            width: 110,
            child: pw.Text(label,
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
          ),
          // Expanded so a very long driver name wraps within the page instead of
          // overflowing off the right edge (no silent truncation).
          pw.Expanded(
            child: pw.Text(value, style: const pw.TextStyle(fontSize: 11)),
          ),
        ],
      ),
    );
  }

  static pw.Widget _table(List<WeekEarning> weeks) {
    final headers = [
      S.pdfColWeek,
      S.pdfColNetIncome,
      S.pdfColRental,
      S.pdfColFuel,
      S.pdfColVat,
      S.pdfColSettlementFee,
      S.pdfColNetProfit,
      S.pdfColHourly,
    ];

    final rows = <List<String>>[
      for (final w in weeks)
        [
          _weekLabel(w),
          formatPln(w.netIncome),
          formatPln(w.rentalFee),
          formatPln(w.fuelAfterDiscount),
          formatPln(w.vat),
          formatPln(w.settlementFee),
          formatPln(w.netProfit),
          formatPln(w.hourlyRate),
        ],
    ];

    const border = pw.TableBorder(
      top: pw.BorderSide(color: PdfColors.black, width: 0.5),
      bottom: pw.BorderSide(color: PdfColors.black, width: 0.5),
      left: pw.BorderSide(color: PdfColors.black, width: 0.5),
      right: pw.BorderSide(color: PdfColors.black, width: 0.5),
      horizontalInside: pw.BorderSide(color: PdfColors.grey600, width: 0.3),
      verticalInside: pw.BorderSide(color: PdfColors.grey600, width: 0.3),
    );

    return pw.TableHelper.fromTextArray(
      border: border,
      headers: headers,
      data: rows,
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
      cellStyle: const pw.TextStyle(fontSize: 9),
      cellHeight: 20,
      headerAlignment: pw.Alignment.centerLeft,
      cellAlignments: {
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.centerRight,
        2: pw.Alignment.centerRight,
        3: pw.Alignment.centerRight,
        4: pw.Alignment.centerRight,
        5: pw.Alignment.centerRight,
        6: pw.Alignment.centerRight,
        7: pw.Alignment.centerRight,
      },
    );
  }

  static pw.Widget _summary(
    double totalNetIncome,
    double totalVat,
    double totalNetProfit,
  ) {
    return pw.Container(
      alignment: pw.Alignment.centerRight,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Text(
            S.pdfTotals,
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11),
          ),
          pw.SizedBox(height: 6),
          _summaryLine(S.pdfSummaryNetIncome, totalNetIncome),
          _summaryLine(S.pdfSummaryVat, totalVat),
          _summaryLine(S.pdfSummaryNetProfit, totalNetProfit, bold: true),
        ],
      ),
    );
  }

  static pw.Widget _summaryLine(String label, double value, {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 3),
      child: pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Text('$label: ',
              style: pw.TextStyle(
                fontSize: bold ? 12 : 10,
                fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
              )),
          pw.Text('${formatPln(value)} PLN',
              style: pw.TextStyle(
                fontSize: bold ? 12 : 10,
                fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
              )),
        ],
      ),
    );
  }

  static String _weekLabel(WeekEarning w) {
    final months = S.months;
    final s = w.weekStart;
    final e = w.weekEnd;
    if (s.month == e.month) {
      return '${s.day}-${e.day} ${months[e.month]} ${e.year}';
    }
    return '${s.day} ${months[s.month]} - ${e.day} ${months[e.month]} ${e.year}';
  }

  static String _two(int v) => v.toString().padLeft(2, '0');
}
