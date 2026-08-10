import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/config/app_config.dart';
import '../../core/providers.dart';
import '../../data/repositories/pat_repository.dart';
import '../components/hope_components.dart';

class ApiTokensScreen extends ConsumerStatefulWidget {
  const ApiTokensScreen({super.key});

  @override
  ConsumerState<ApiTokensScreen> createState() => _ApiTokensScreenState();
}

class _ApiTokensScreenState extends ConsumerState<ApiTokensScreen> {
  List<PersonalAccessToken>? _tokens;
  String? _error;

  static String get _mcpUrl =>
      '${AppConfig.apiBaseUrl}${AppConfig.apiPrefix}/ai/mcp';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final tokens = await ref.read(patRepositoryProvider).list();
      if (mounted) setState(() { _tokens = tokens; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _generate() async {
    final result = await showDialog<(String, String, int?)>(
      context: context,
      builder: (_) => const _GenerateTokenDialog(),
    );
    if (result == null) return;
    final (name, kind, expiresInDays) = result;
    try {
      final created = await ref.read(patRepositoryProvider).create(
        name: name,
        kind: kind,
        expiresInDays: expiresInDays,
      );
      await _load();
      if (mounted) {
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => _TokenRevealDialog(created: created, mcpUrl: _mcpUrl),
        );
      }
    } catch (e) {
      if (mounted) showHopeSnack(context, e.toString(), tone: HopeSnackTone.danger);
    }
  }

  Future<void> _revoke(PersonalAccessToken token) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(token.isOAuth ? 'Desconectar app?' : 'Revogar token?'),
        content: Text(
          token.isOAuth
              ? '"${token.displayName}" perde o acesso à sua conta imediatamente. '
                'Para usar de novo, será preciso autorizar outra vez pelo app.'
              : '"${token.displayName}" deixará de funcionar imediatamente em '
                'qualquer lugar onde esteja configurado.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(token.isOAuth ? 'Desconectar' : 'Revogar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(patRepositoryProvider).revoke(token.id);
      await _load();
      if (mounted) {
        showHopeSnack(
          context,
          token.isOAuth ? 'App desconectado' : 'Token revogado',
          tone: HopeSnackTone.success,
        );
      }
    } catch (e) {
      if (mounted) showHopeSnack(context, e.toString(), tone: HopeSnackTone.danger);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final connections = _tokens?.where((t) => t.isMcp).toList()
      // Apps que se conectaram sozinhos primeiro; entre iguais, o mais recente.
      ?..sort((a, b) {
        if (a.isOAuth != b.isOAuth) return a.isOAuth ? -1 : 1;
        return b.createdAt.compareTo(a.createdAt);
      });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Apps conectados'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Mais opções',
            onSelected: (value) {
              if (value == 'manual') _generate();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'manual',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.key_outlined),
                  title: Text('Gerar token manual'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _ConnectCard(mcpUrl: _mcpUrl),
            const SizedBox(height: 20),
            if (_error != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(_error!, style: TextStyle(color: scheme.error)),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Tentar novamente'),
                      ),
                    ],
                  ),
                ),
              )
            else if (connections == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text(
                  connections.isEmpty
                      ? 'Nenhum app conectado'
                      : 'Com acesso à sua conta (${connections.length})',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              if (connections.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                  child: Text(
                    'Quando você autorizar um app, ele aparece aqui e pode ser '
                    'desconectado a qualquer momento.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                )
              else
                for (final token in connections)
                  _ConnectionCard(
                    token: token,
                    onRevoke: () => _revoke(token),
                  ),
            ],
            const SizedBox(height: 24),
            _AdvancedSection(onGenerate: _generate),
          ],
        ),
      ),
    );
  }
}

/// Passo a passo de conexão. A URL do MCP virou o elemento principal da tela:
/// para hosts que fazem OAuth (ChatGPT e afins) ela é a ÚNICA coisa que o
/// usuário precisa levar — o token é emitido sozinho no fim da autorização.
class _ConnectCard extends StatelessWidget {
  const _ConnectCard({required this.mcpUrl});

  final String mcpUrl;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: scheme.primary.withValues(alpha: 0.12),
                  child: Icon(Icons.hub_outlined, color: scheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Conectar um app',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Informe esta URL no app de IA que você quiser usar. '
                        'Ele abre o login do HopeCash, você escolhe o nível de '
                        'acesso e pronto — nenhum token para copiar.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _CopyableField(label: 'URL do MCP', value: mcpUrl),
          ],
        ),
      ),
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({required this.token, required this.onRevoke});

  final PersonalAccessToken token;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: scheme.primary.withValues(alpha: 0.12),
              child: Icon(
                token.isOAuth ? Icons.smart_toy_outlined : Icons.key_outlined,
                color: scheme.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(token.displayName, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _Tag(
                        label: token.canWrite ? 'Leitura e escrita' : 'Somente leitura',
                        icon: token.canWrite
                            ? Icons.edit_outlined
                            : Icons.visibility_outlined,
                        tone: token.canWrite ? scheme.tertiary : scheme.onSurfaceVariant,
                      ),
                      _Tag(
                        label: token.isOAuth ? 'Autorizado pelo app' : 'Token manual',
                        icon: token.isOAuth
                            ? Icons.verified_user_outlined
                            : Icons.content_paste_outlined,
                        tone: scheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _activityLine(token),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: token.isOAuth ? 'Desconectar' : 'Revogar',
              icon: Icon(Icons.link_off_rounded, color: scheme.error),
              onPressed: onRevoke,
            ),
          ],
        ),
      ),
    );
  }

  static String _activityLine(PersonalAccessToken token) {
    final df = DateFormat('dd/MM/yyyy');
    final parts = <String>[
      token.lastUsedAt != null
          ? 'Última atividade em ${df.format(token.lastUsedAt!)}'
          : 'Nunca usado',
      'conectado em ${df.format(token.createdAt)}',
    ];
    if (token.expiresAt != null) {
      parts.add('expira em ${df.format(token.expiresAt!)}');
    }
    // O sufixo do token só interessa para conferir qual é qual num cliente
    // configurado na mão; para conexão OAuth é ruído.
    if (!token.isOAuth && token.last4.isNotEmpty) {
      parts.add('termina em ${token.last4}');
    }
    return parts.join(' · ');
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.icon, required this.tone});

  final String label;
  final IconData icon;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: tone),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: tone),
          ),
        ],
      ),
    );
  }
}

/// Geração manual de token: continua existindo porque clientes de
/// desenvolvedor (Claude Code, n8n, scripts) usam Bearer estático em vez de
/// OAuth — mas deixou de ser a ação principal da tela.
class _AdvancedSection extends StatelessWidget {
  const _AdvancedSection({required this.onGenerate});

  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          leading: Icon(Icons.tune_rounded, color: scheme.onSurfaceVariant),
          title: Text('Uso avançado', style: Theme.of(context).textTheme.titleSmall),
          subtitle: Text(
            'Token manual para ferramentas sem login automático',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Alguns clientes — Claude Code, automações, scripts — não fazem '
                'o login automático e precisam de um token colado na configuração. '
                'Quem tiver esse token acessa sua conta como se fosse você, dentro '
                'do escopo escolhido, então guarde-o com cuidado.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: onGenerate,
                icon: const Icon(Icons.key_outlined),
                label: const Text('Gerar token manual'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GenerateTokenDialog extends StatefulWidget {
  const _GenerateTokenDialog();

  @override
  State<_GenerateTokenDialog> createState() => _GenerateTokenDialogState();
}

class _GenerateTokenDialogState extends State<_GenerateTokenDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController(text: 'Claude');
  String _kind = 'mcp_read';
  int? _expiresInDays;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Gerar token de API'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Nome',
                helperText: 'Para você reconhecer depois, ex.: "Claude Desktop"',
                prefixIcon: Icon(Icons.label_outline),
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe um nome' : null,
            ),
            const SizedBox(height: 16),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'mcp_read',
                  label: Text('Somente leitura'),
                  icon: Icon(Icons.visibility_outlined),
                ),
                ButtonSegment(
                  value: 'mcp_write',
                  label: Text('Leitura e escrita'),
                  icon: Icon(Icons.edit_outlined),
                ),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() => _kind = s.first),
            ),
            const SizedBox(height: 8),
            Text(
              _kind == 'mcp_read'
                  ? 'Consulta saldos, lançamentos, orçamento etc. Não altera nada.'
                  : 'Além de consultar, pode propor lançamentos — cada um exige '
                    'confirmação explícita antes de valer.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int?>(
              initialValue: _expiresInDays,
              decoration: const InputDecoration(
                labelText: 'Expiração',
                prefixIcon: Icon(Icons.schedule_outlined),
              ),
              items: const [
                DropdownMenuItem(value: null, child: Text('Nunca expira')),
                DropdownMenuItem(value: 30, child: Text('30 dias')),
                DropdownMenuItem(value: 90, child: Text('90 dias')),
                DropdownMenuItem(value: 365, child: Text('1 ano')),
              ],
              onChanged: (v) => setState(() => _expiresInDays = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(context, (_name.text.trim(), _kind, _expiresInDays));
          },
          child: const Text('Gerar'),
        ),
      ],
    );
  }
}

class _TokenRevealDialog extends StatelessWidget {
  const _TokenRevealDialog({required this.created, required this.mcpUrl});

  final CreatedPersonalAccessToken created;
  final String mcpUrl;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Token gerado'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: scheme.errorContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: scheme.error, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Copie agora — este token só é exibido uma vez.',
                      style: TextStyle(color: scheme.onErrorContainer),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _CopyableField(label: 'Token', value: created.token),
            const SizedBox(height: 12),
            _CopyableField(label: 'URL do MCP', value: mcpUrl),
            const SizedBox(height: 16),
            Text(
              'Configure o host MCP com esses dois valores (URL + Bearer token). '
              'Veja docs/MCP.md no repositório para exemplos completos.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Entendi, copiei'),
        ),
      ],
    );
  }
}

class _CopyableField extends StatelessWidget {
  const _CopyableField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Expanded(
                child: SelectableText(
                  value,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                ),
              ),
              IconButton(
                tooltip: 'Copiar',
                icon: const Icon(Icons.copy_outlined, size: 18),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: value));
                  if (context.mounted) {
                    showHopeSnack(context, '$label copiado', tone: HopeSnackTone.success);
                  }
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}
