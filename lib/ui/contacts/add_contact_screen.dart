import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../state/auth_store.dart';
import '../common.dart';
import '../widgets/account_type_avatar.dart';

class AddContactScreen extends StatefulWidget {
  const AddContactScreen({super.key});

  @override
  State<AddContactScreen> createState() => _AddContactScreenState();
}

class _AddContactScreenState extends State<AddContactScreen> {
  final _username = TextEditingController();
  final _scroll = ScrollController();
  final _resultsKey = GlobalKey();
  List<Map<String, dynamic>> _results = [];
  bool _searching = false;
  bool _adding = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _scroll.dispose();
    super.dispose();
  }

  bool _isOnline(Map<String, dynamic> account) {
    final type = account['type_code'];
    final business = type != null && type != 'personal';
    return business
        ? account['is_active'] == true
        : account['is_online'] == true;
  }

  Future<void> _search() async {
    // Hide the keyboard first: the result card sits below the search button
    // and was previously hidden behind the keyboard on phones.
    FocusScope.of(context).unfocus();
    final handle = normalizeUsername(_username.text);
    if (!validUsername(handle)) {
      setState(() {
        _error = 'Username tidak valid.';
        _results = [];
      });
      return;
    }
    setState(() {
      _searching = true;
      _error = null;
      _results = [];
    });
    try {
      final data = await context.read<AuthStore>().api.get(
        'accounts/lookup',
        query: {'handle': handle},
      );
      if (!mounted) return;
      final raw = data is Map ? data['accounts'] : null;
      final single = data is Map ? data['account'] : null;
      final list = raw is List && raw.isNotEmpty
          ? raw
          : (single is Map ? <Object>[single] : const <Object>[]);
      final results = list
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      setState(() {
        _results = results;
        if (_results.isEmpty) _error = 'Akun tidak ditemukan.';
      });
      if (results.isNotEmpty) {
        // Wait for the keyboard to collapse before revealing the result card,
        // otherwise the card stays below the old viewport.
        await Future.delayed(const Duration(milliseconds: 350));
        if (!mounted) return;
        final contextResult = _resultsKey.currentContext;
        if (contextResult != null) {
          await Scrollable.ensureVisible(
            contextResult,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            alignment: 0.05,
          );
        } else if (_scroll.hasClients) {
          await _scroll.animateTo(
            _scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _add(Map<String, dynamic> account) async {
    if (_adding) return;
    setState(() => _adding = true);
    try {
      await context.read<AuthStore>().api.post('contacts', {
        'account_id': account['account_id'],
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('${account['display_name']} ditambahkan ke kontak.')),
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tambah kontak')),
      body: ReadableWidth(
        maxWidth: 640,
        child: ListView(
          controller: _scroll,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Cari akun menggunakan username, misalnya @aska.development.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _username,
              autocorrect: false,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                labelText: 'Username',
                prefixText: '@',
                prefixIcon: Icon(Icons.alternate_email),
              ),
              onSubmitted: (_) => _search(),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _searching ? null : _search,
              icon: _searching
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.search),
              label: const Text('Cari akun'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            if (_results.isNotEmpty) ...[
              const SizedBox(height: 18),
              Row(
                key: _resultsKey,
                children: [
                  Text(
                    'Hasil pencarian',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '(${_results.length})',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ],
            for (final account in _results) ...[
              const SizedBox(height: 10),
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                  child: Row(
                    children: [
                      AccountTypeAvatar(
                        account: account,
                        radius: 24,
                        token: context.read<AuthStore>().api.accessToken,
                        showStatusDot: _isOnline(account),
                        backgroundColor:
                            typeColor(account['type_code'] as String?)
                                .withValues(alpha: 0.15),
                        foregroundColor:
                            typeColor(account['type_code'] as String?),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${account['display_name'] ?? account['handle'] ?? 'Akun'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                            Text(
                              '@${account['handle'] ?? ''}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                            if (_isOnline(account)) ...[
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF22C55E),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  const Text(
                                    'Online',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF16A34A),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: _adding ? null : () => _add(account),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: const Icon(Icons.person_add_alt_1, size: 16),
                        label: const Text('Tambah'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
