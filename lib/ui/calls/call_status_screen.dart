import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/call_service.dart';
import '../widgets/account_type_avatar.dart';

/// Outgoing direct call screen. Once the callee answers it opens the Jitsi
/// call UI and closes when the call ends.
class CallStatusScreen extends StatefulWidget {
  const CallStatusScreen({
    super.key,
    required this.call,
    required this.jitsi,
  });

  final Map<String, dynamic> call;
  final Map<String, dynamic> jitsi;

  @override
  State<CallStatusScreen> createState() => _CallStatusScreenState();
}

class _CallStatusScreenState extends State<CallStatusScreen> {
  bool _joined = false;
  bool _closing = false;
  Timer? _poll;

  int? get _callId => widget.call['call_id'] as int?;

  @override
  void initState() {
    super.initState();
    CallService.instance.addListener(_onCallChanged);
    final callId = _callId;
    if (callId != null) {
      _poll = Timer.periodic(
        const Duration(seconds: 3),
        (_) => CallService.instance.refreshCall(callId),
      );
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    CallService.instance.removeListener(_onCallChanged);
    super.dispose();
  }

  Future<void> _onCallChanged() async {
    if (!mounted || _joined || _closing) return;
    final active = CallService.instance.activeCall;
    if (active != null && active['call_id'] == _callId) {
      _joined = true;
      _poll?.cancel();
      await CallService.instance.joinJitsi(
        widget.jitsi,
        kind: '${widget.call['kind'] ?? 'voice'}',
        callId: _callId,
      );
      if (mounted && !_closing) {
        _closing = true;
        Navigator.of(context).maybePop();
      }
      return;
    }
    if (CallService.instance.outgoingCall == null) {
      // The callee declined or the call expired before it was answered.
      _closing = true;
      _poll?.cancel();
      if (mounted) Navigator.of(context).maybePop();
    }
  }

  Future<void> _hangUp() async {
    if (_closing) return;
    _closing = true;
    final callId = _callId;
    if (callId != null) await CallService.instance.cancelOutgoing(callId);
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final peer = widget.call['peer'] is Map
        ? Map<String, dynamic>.from(widget.call['peer'] as Map)
        : <String, dynamic>{};
    final kind = '${widget.call['kind'] ?? 'voice'}';
    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            AccountTypeAvatar(
              account: peer,
              radius: 48,
              showStatusDot: false,
            ),
            const SizedBox(height: 20),
            Text(
              '${peer['display_name'] ?? 'Panggilan'}',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              kind == 'video' ? 'Panggilan video…' : 'Memanggil…',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const Spacer(),
            IconButton.filled(
              onPressed: _hangUp,
              style: IconButton.styleFrom(
                backgroundColor: scheme.error,
                foregroundColor: scheme.onError,
                minimumSize: const Size(64, 64),
              ),
              icon: const Icon(Icons.call_end, size: 30),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
