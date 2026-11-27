import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/call_service.dart';

/// Hosts the Jitsi web app inside a WebView. The native Jitsi SDK was dropped
/// because its bundled web app did not match this server version and showed
/// "You have been disconnected".
class CallWebViewScreen extends StatefulWidget {
  const CallWebViewScreen({
    super.key,
    required this.serverUrl,
    required this.room,
    required this.token,
    required this.title,
    this.video = false,
    this.callId,
  });

  final String serverUrl;
  final String room;
  final String token;
  final String title;
  final bool video;
  final int? callId;

  @override
  State<CallWebViewScreen> createState() => _CallWebViewScreenState();
}

class _CallWebViewScreenState extends State<CallWebViewScreen> {
  InAppWebViewController? _controller;
  bool _failed = false;
  bool _ended = false;
  Timer? _watch;
  DateTime? _joinedAt;

  static const _leftCheckJs = r'''
(function () {
  try {
    if (window.APP && APP.conference) {
      var room = APP.conference._room;
      if (room && room.isLeft && room.isLeft()) return 'left';
      if (room && room.getMyUserId && !room.getMyUserId()) return 'left';
    }
  } catch (e) {}
  try {
    if (location.href === 'about:blank') return 'left';
    if (location.pathname === '/' || location.pathname === '') return 'left';
  } catch (e) {}
  try {
    var text = (document.body && document.body.innerText || '').toLowerCase();
    if (text.indexOf('you have left the meeting') >= 0) return 'left';
    if (text.indexOf('you left the meeting') >= 0) return 'left';
    if (text.indexOf('kembali ke rapat') >= 0) return 'left';
  } catch (e) {}
  return 'in';
})()
''';

  late final String _url = _buildUrl();

  @override
  void initState() {
    super.initState();
    CallService.instance.endSignal.addListener(_onEndSignal);
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    await Permission.microphone.request();
    if (widget.video) await Permission.camera.request();
  }

  @override
  void dispose() {
    _watch?.cancel();
    CallService.instance.endSignal.removeListener(_onEndSignal);
    super.dispose();
  }

  void _startWatch() {
    _watch?.cancel();
    _watched = false;
    _watch = Timer.periodic(const Duration(seconds: 2), (_) => _checkLeft());
  }

  bool _watched = false;

  Future<void> _checkLeft() async {
    if (_ended || _failed || _controller == null) return;
    if (_joinedAt != null &&
        DateTime.now().difference(_joinedAt!) < const Duration(seconds: 4)) {
      return;
    }
    try {
      final result =
          await _controller!.evaluateJavascript(source: _leftCheckJs);
      if ('$result'.toLowerCase() == 'left' && !_ended) {
        await _endCall();
      }
    } catch (_) {}
  }

  void _onEndSignal() {
    if (CallService.instance.endSignal.value == widget.callId) {
      CallService.instance.endSignal.value = null;
      _endCall();
    }
  }

  String _buildUrl() {
    final base = widget.serverUrl.replaceFirst(RegExp(r'/+$'), '');
    final params = <String, String>{
      'jwt': widget.token,
      'config.prejoinPageEnabled': 'false',
      'config.prejoinConfig.enabled': 'false',
      'config.startWithAudioMuted': 'false',
      'config.startWithVideoMuted': widget.video ? 'false' : 'true',
      'config.disableDeepLinking': 'true',
      'config.requireDisplayName': 'false',
      'config.subject': 'Sekitarin',
      'config.enableWelcomePage': 'false',
      'config.hideConferenceSubject': 'true',
    };
    final hash = params.entries
        .map((entry) => '${entry.key}=${Uri.encodeComponent(entry.value)}')
        .join('&');
    // Some WebViews drop the URL fragment before the Jitsi app reads it.
    // Jitsi accepts the JWT from the query string too, so send it twice.
    final tokenQuery =
        widget.token.isEmpty ? '' : '?jwt=${Uri.encodeComponent(widget.token)}';
    return '$base/${widget.room}$tokenQuery#$hash';
  }

  Future<void> _endCall() async {
    if (_ended) return;
    _ended = true;
    await _controller?.loadUrl(
      urlRequest: URLRequest(url: WebUri('about:blank')),
    );
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _confirmEnd() async {
    final confirmed = await showDialog<bool>(
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
    if (confirmed == true) await _endCall();
  }

  Future<void> _openInBrowser() async {
    try {
      await launchUrl(Uri.parse(_url), mode: LaunchMode.externalApplication);
      await _endCall();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _confirmEnd();
      },
      child: Scaffold(
        appBar: AppBar(
          title:
              Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(
              onPressed: _confirmEnd,
              icon: const Icon(Icons.call_end),
              tooltip: 'Akhiri panggilan',
            ),
          ],
        ),
        body: _failed
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.videocam_off_outlined,
                          size: 48, color: scheme.error),
                      const SizedBox(height: 12),
                      const Text(
                        'Panggilan tidak dapat dibuka di aplikasi.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _openInBrowser,
                        icon: const Icon(Icons.open_in_browser),
                        label: const Text('Buka di browser'),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => setState(() {
                          _failed = false;
                        }),
                        child: const Text('Coba lagi'),
                      ),
                    ],
                  ),
                ),
              )
            : InAppWebView(
                initialUrlRequest: URLRequest(url: WebUri(_url)),
                initialSettings: InAppWebViewSettings(
                  mediaPlaybackRequiresUserGesture: false,
                  javaScriptEnabled: true,
                  domStorageEnabled: true,
                  databaseEnabled: true,
                  allowsInlineMediaPlayback: true,
                  useHybridComposition: true,
                  supportMultipleWindows: false,
                  thirdPartyCookiesEnabled: true,
                  isInspectable: false,
                  clearCache: false,
                ),
                onWebViewCreated: (controller) {
                  _controller = controller;
                },
                onLoadStop: (controller, url) {
                  if (!_watched) {
                    _watched = true;
                    _joinedAt = DateTime.now();
                    _startWatch();
                  }
                },
                onPermissionRequest: (controller, request) async {
                  final statuses = await [
                    Permission.microphone,
                    Permission.camera,
                  ].request();
                  final granted = <PermissionResourceType>[];
                  if (statuses[Permission.microphone]?.isGranted == true) {
                    granted.add(PermissionResourceType.MICROPHONE);
                  }
                  if (statuses[Permission.camera]?.isGranted == true) {
                    granted.add(PermissionResourceType.CAMERA);
                  }
                  return PermissionResponse(
                    resources: granted,
                    action: granted.isEmpty
                        ? PermissionResponseAction.DENY
                        : PermissionResponseAction.GRANT,
                  );
                },
                onReceivedError: (controller, request, error) {
                  if (request.isForMainFrame == true) {
                    setState(() => _failed = true);
                  }
                },
              ),
      ),
    );
  }
}
