import 'package:flutter_test/flutter_test.dart';
import 'package:hopecash/data/remote/ai_api.dart';

void main() {
  test('AiAction interpreta proposta e aplica o desfecho da confirmação', () {
    final action = AiAction.fromJson({
      'id': 'action-1',
      'tool_name': 'create_transaction',
      'status': 'proposed',
      'expires_at': '2026-07-15 12:15:00.000',
      'summary': {
        'title': 'Nova despesa',
        'fields': [
          {'label': 'Valor', 'value': 50, 'kind': 'money'},
        ],
      },
    });

    expect(action.status, 'proposed');
    expect(action.summary['title'], 'Nova despesa');

    action.apply(
      AiAction.fromJson({
        'id': 'action-1',
        'tool_name': 'create_transaction',
        'status': 'confirmed',
        'expires_at': '2026-07-15 12:15:00.000',
        'summary': action.summary,
        'result': {'id': 'transaction-1'},
      }),
    );

    expect(action.status, 'confirmed');
    expect(action.result, {'id': 'transaction-1'});
  });
}
