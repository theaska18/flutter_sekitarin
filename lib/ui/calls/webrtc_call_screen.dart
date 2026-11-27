import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../services/call_service.dart';
import '../../services/jitsi/jitsi_call_client.dart';

/// Custom in-call screen backed by flutter_webrtc + Jitsi XMPP signaling.
class WebrtcCallScreen extends StatefulWidget {
  const WebrtcCallScreen({
    super.key,
    required this.serverUrl,
    required this.host,
    required this.xmppDomain,
    required this.room,
    required this.token,
    required this.displayName,
    required this.title,
    required this.video,
    this.callId,
  });

  final String serverUrl;
  final String host;
  final String xmppDomain;
  final String room;
  final String token;
  final String displayName;
  final String title;
  final bool video;
  final int? callId;

  @override
  State<WebrtcCallScreen> createState() => _WebrtcCallScreenState();
}

class _WebrtcCallScreenState extends State<WebrtcCallScreen> {
  late final JitsiCallClient _client;
  bool _connected = false;
  bool _closing = false;
  String? _error;
  bool _muted = false;
  bool _cameraOff = true;
  bool _speaker = true;

  @override
  void initState() {
    super.initState();
    _client = JitsiCallClient(
      serverUrl: widget.serverUrl,
      host: widget.host,
      xmppDomain: widget.xmppDomain,
      room: widget.room,
      token: widget.token,
      displayName: widget.displayName,
      startWithVideo: widget.video,
      onUpdate: () {
        if (!mounted) return;
        setState(() {
          _connected = _client.connected;
          _error = _client.error;
          _muted = _client.audioMuted;
          _cameraOff = _client.videoMuted;
        });
      },
      onConnected: () {
        if (!mounted) return;
        setState(() {
          _connected = true;
          _error = null;
        });
      },
      onEnded: () {
        if (!mounted || _closing) return;
        _closing = true;
        Navigator.of(context).pop(true);
      },
      onFailed: (message) {
        if (!mounted) return;
        setState(() => _error = message);
        // Give the user a brief moment, then let CallService fall back to the
        // in-app Jitsi web view.
        Future.delayed(const Duration(milliseconds: 1200), () async {
          if (!mounted || _closing || _connected) return;
          _closing = true;
          await _client.hangUp();
          if (mounted) Navigator.of(context).pop(false);
        });
      },
    );
    CallService.instance.endSignal.addListener(_onRemoteEnd);
    _client.connect();
  }

  void _onRemoteEnd() {
    if (!mounted || _closing) return;
    if (CallService.instance.endSignal.value != widget.callId) return;
    CallService.instance.endSignal.value = null;
    _closing = true;
    _client.hangUp();
    Navigator.of(context).pop(true);
  }

  @override
  void dispose() {
    CallService.instance.endSignal.removeListener(_onRemoteEnd);
    _client.hangUp();
    super.dispose();
  }

  Future<void> _hangUp() async {
    if (_closing) return;
    _closing = true;
    await _client.hangUp();
    if (mounted) Navigator.of(context).pop(_connected);
  }

  Future<void> _confirmClose() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Akhiri panggilan?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Akhiri'),
          ),
        ],
      ),
    );
    if (result == true) await _hangUp();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final remoteRenderer = _client.remoteRenderer;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _confirmClose();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            Positioned.fill(
              child: remoteRenderer != null && remoteRenderer.srcObject != null
                  ? RTCVideoView(
                      remoteRenderer,
                      objectFit:
                          RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    )
                  : ColoredBox(
                      color: const Color(0xFF101417),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircleAvatar(
                              radius: 48,
                              backgroundColor: scheme.primary,
                              child: Text(
                                widget.title.isEmpty
                                    ? '?'
                                    : widget.title.characters.first
                                        .toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 36,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              widget.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _error ??
                                  (_connected
                                      ? _client.callDuration
                                      : _client.stage),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: _error != null
                                    ? scheme.error
                                    : Colors.white70,
                              ),
                            ),
                            if (!_connected && _error == null) ...[
                              const SizedBox(height: 20),
                              const SizedBox(
                                width: 26,
                                height: 26,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                  color: Colors.white70,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
            ),
            if (!_cameraOff && _client.localRenderer.srcObject != null)
              Positioned(
                top: MediaQuery.of(context).padding.top + 12,
                right: 12,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 96,
                    height: 128,
                    child: RTCVideoView(
                      _client.localRenderer,
                      mirror: true,
                      objectFit:
                          RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    ),
                  ),
                ),
              ),
            Positioned(
              top: MediaQuery.of(context).padding.top + 12,
              left: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (_connected)
                    Text(
                      _client.callDuration,
                      style: const TextStyle(color: Colors.white70),
                    ),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: MediaQuery.of(context).padding.bottom + 24,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _RoundButton(
                    icon: _muted ? Icons.mic_off : Icons.mic,
                    active: _muted,
                    onPressed: () async {
                      await _client.toggleAudio();
                      if (mounted) setState(() => _muted = _client.audioMuted);
                    },
                  ),
                  _RoundButton(
                    icon: _cameraOff ? Icons.videocam_off : Icons.videocam,
                    active: _cameraOff,
                    onPressed: () async {
                      await _client.toggleVideo();
                      if (mounted) {
                        setState(() => _cameraOff = _client.videoMuted);
                      }
                    },
                  ),
                  _RoundButton(
                    icon: Icons.cameraswitch_outlined,
                    onPressed: () => _client.switchCamera(),
                  ),
                  _RoundButton(
                    icon: _speaker ? Icons.volume_up : Icons.volume_off,
                    onPressed: () async {
                      await _client.toggleSpeaker();
                      if (mounted) setState(() => _speaker = _client.speakerOn);
                    },
                  ),
                  _RoundButton(
                    icon: Icons.call_end,
                    danger: true,
                    onPressed: _hangUp,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.onPressed,
    this.active = false,
    this.danger = false,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final bool active;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final background = danger
        ? const Color(0xFFD93025)
        : active
            ? Colors.white
            : Colors.white24;
    final foreground = danger
        ? Colors.white
        : active
            ? Colors.black87
            : Colors.white;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Material(
        color: background,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Icon(icon, color: foreground, size: 24),
          ),
        ),
      ),
    );
  }
}
