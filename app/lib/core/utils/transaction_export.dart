import 'package:excel/excel.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../data/local/database.dart';
import 'money.dart';

/// MIME type de uma planilha .xlsx.
const xlsxMimeType =
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
const pdfMimeType = 'application/pdf';

/// Gera os bytes de uma planilha .xlsx com os [transactions] informados,
/// resolvendo nomes de categoria/conta/cartão pelos mapas fornecidos.
///
/// Valores monetários são gravados como número (para permitir somas no Excel);
/// datas e textos, como texto legível.
List<int> buildTransactionsXlsx({
  required List<LocalTransaction> transactions,
  required Map<String, String> categoryNames,
  required Map<String, String> accountNames,
  required Map<String, String> cardNames,
}) {
  final excel = Excel.createExcel();
  final defaultSheet = excel.getDefaultSheet();
  final sheet = excel['Lançamentos'];
  excel.setDefaultSheet('Lançamentos');
  if (defaultSheet != null && defaultSheet != 'Lançamentos') {
    excel.delete(defaultSheet);
  }

  sheet.appendRow([
    TextCellValue('Data'),
    TextCellValue('Vencimento'),
    TextCellValue('Tipo'),
    TextCellValue('Descrição'),
    TextCellValue('Categoria'),
    TextCellValue('Origem'),
    TextCellValue('Status'),
    TextCellValue('Previsto'),
    TextCellValue('Realizado'),
  ]);

  for (final t in transactions) {
    final isCard = t.cardId != null && t.cardId!.isNotEmpty;
    final origin = isCard
        ? (cardNames[t.cardId] ?? 'Cartão')
        : (accountNames[t.accountId] ?? '');
    sheet.appendRow([
      TextCellValue(formatDate(t.competenceDate)),
      TextCellValue(formatDate(t.dueDate)),
      TextCellValue(t.type == 'income' ? 'Receita' : 'Despesa'),
      TextCellValue(t.description),
      TextCellValue(categoryNames[t.categoryId] ?? ''),
      TextCellValue(origin),
      TextCellValue(_statusLabel(t)),
      DoubleCellValue(t.amountPlanned ?? t.amount ?? 0),
      DoubleCellValue(t.amount ?? 0),
    ]);
  }

  return excel.encode() ?? <int>[];
}

String _statusLabel(LocalTransaction t) => switch (t.status) {
  'paid' => t.type == 'income' ? 'Recebido' : 'Pago',
  'planned' => 'Previsto',
  'overdue' => 'Atrasado',
  'canceled' => 'Cancelado',
  _ => t.status,
};

/// Gera um PDF simples e paginado com os lançamentos já filtrados na tela.
Future<List<int>> buildTransactionsPdf({
  required List<LocalTransaction> transactions,
  required Map<String, String> categoryNames,
  required Map<String, String> accountNames,
  required Map<String, String> cardNames,
  required String title,
}) {
  final document = pw.Document();
  document.addPage(
    pw.MultiPage(
      header: (_) => pw.Header(level: 0, child: pw.Text(title)),
      build: (_) => [
        pw.TableHelper.fromTextArray(
          headers: const [
            'Data',
            'Vencimento',
            'Tipo',
            'Descrição',
            'Categoria',
            'Origem',
            'Status',
            'Previsto',
            'Realizado',
          ],
          data: [
            for (final t in transactions)
              [
                formatDate(t.competenceDate),
                formatDate(t.dueDate),
                t.type == 'income' ? 'Receita' : 'Despesa',
                t.description,
                categoryNames[t.categoryId] ?? '',
                t.cardId != null
                    ? (cardNames[t.cardId] ?? 'Cartão')
                    : (accountNames[t.accountId] ?? ''),
                _statusLabel(t),
                (t.amountPlanned ?? t.amount ?? 0).toStringAsFixed(2),
                (t.amount ?? 0).toStringAsFixed(2),
              ],
          ],
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          cellStyle: const pw.TextStyle(fontSize: 7),
          cellPadding: const pw.EdgeInsets.all(3),
          border: pw.TableBorder.all(width: .3),
        ),
      ],
    ),
  );
  return document.save();
}
