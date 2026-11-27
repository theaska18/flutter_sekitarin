import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:xml/xml.dart';

import 'jitsi_participant.dart';
import 'jitsi_sdp_helper.dart';
import 'xmpp_utils.dart' as xmpp_utils;

/// Minimal Jitsi client: connects to the Jitsi XMPP websocket, joins the MUC,
/// negotiates Jingle with Jicofo and renders media with flutter_webrtc.
///
/// This is a trimmed port of the InfinityOne implementation used on branch
/// ISP-2194; it intentionally supports a single 1:1/group room without the
/// extra Jitsi features (transcription, screen share, E2EE, ...).
class JitsiCallClient implements JitsiSessionView {
  JitsiCallClient({
    required this.serverUrl,
    required this.host,
    required this.xmppDomain,
    required this.room,
    required this.token,
    required this.displayName,
    this.avatarUrl = '',
    this.startWithVideo = false,
    this.onUpdate,
    this.onConnected,
    this.onEnded,
    this.onFailed,
  });

  final String serverUrl;
  final String host;
  final String xmppDomain;
  final String room;
  final String token;
  final String displayName;
  final String avatarUrl;
  final bool startWithVideo;
  final VoidCallback? onUpdate;
  final VoidCallback? onConnected;
  final VoidCallback? onEnded;
  final void Function(String message)? onFailed;

  final Uuid _uuid = const Uuid();
  late final JitsiSdpHelper _sdp = JitsiSdpHelper(this);

  @override
  final List<JitsiParticipant> participants = [];
  @override
  String sdpApplication = '';
  @override
  String sdpDataMid = '2';

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  RTCPeerConnection? pc;
  MediaStream? localStream;
  RTCDataChannel? _dataChannel;
  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final Map<String, RTCVideoRenderer> remoteRenderers = {};
  RTCVideoRenderer? remoteRenderer;

  String jid = '';
  String nick = '';
  String focusJid = '';
  String? jingleSid;
  String? bridgeSession;
  List<Map<String, dynamic>> _iceServers = [];
  Map<String, Map<String, dynamic>> _sdpMap = {};
  Timer? _connectTimer;
  Timer? _durationTimer;
  DateTime? _connectedAt;

  bool audioMuted = false;
  bool videoMuted = true;
  bool speakerOn = true;
  bool connected = false;
  bool closed = false;
  String stage = 'Menyiapkan panggilan';
  String? error;
  String callDuration = '';

  String get _roomJid => '$room@muc.$xmppDomain';

  Future<void> connect() async {
    await localRenderer.initialize();
    await _openMedia();
    _connectTimer = Timer(const Duration(seconds: 25), () {
      if (!connected) _fail('Server tidak merespons panggilan.');
    });
    _connectSocket();
  }

  Future<void> _openMedia() async {
    try {
      final constraints = <String, dynamic>{
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': startWithVideo
            ? {
                'facingMode': 'user',
                'width': {'ideal': 1280},
                'height': {'ideal': 720},
              }
            : false,
      };
      localStream = await navigator.mediaDevices.getUserMedia(constraints);
      localRenderer.srcObject = localStream;
      if (startWithVideo) videoMuted = false;
      _notify();
    } catch (e) {
      _fail('Tidak dapat mengakses mikrofon/kamera: $e');
    }
  }

  void _connectSocket() {
    final url =
        'wss://$host/xmpp-websocket?room=${Uri.encodeQueryComponent(room)}&token=${Uri.encodeQueryComponent(token)}';
    try {
      final channel = WebSocketChannel.connect(Uri.parse(url));
      _channel = channel;
      _sub = channel.stream.listen(
        (raw) => _onStanza('$raw'),
        onError: (e) => _transportClosed('$e'),
        onDone: () => _transportClosed('closed'),
      );
      _send(
        '<open to="$xmppDomain" version="1.0" xmlns="urn:ietf:params:xml:ns:xmpp-framing"/>',
      );
      stage = 'Menghubungkan ke server';
      _notify();
    } catch (e) {
      _fail('Gagal menghubungkan ke server: $e');
    }
  }

  void _send(String xml) {
    final channel = _channel;
    if (channel == null) return;
    try {
      channel.sink.add(xml);
    } catch (_) {}
  }

  String _iqId() => '${_uuid.v4()}:sendIQ';
  String _bindId = '';
  String _sessionId = '';
  String _discoId = '';
  String _conferenceId = '';

  void _onStanza(String msg) {
    if (msg.trim().isEmpty) return;
    try {
      if (msg.contains('<iq') && xmpp_utils.isPingQuery(msg)) {
        final doc = XmlDocument.parse(msg);
        final id = doc.rootElement.getAttribute('id');
        final from = doc.rootElement.getAttribute('from');
        if (id != null && from != null) {
          _send(xmpp_utils.buildPingResult(id: id, to: from));
        }
        return;
      }
      if (msg.contains('<iq') && xmpp_utils.isDiscoInfoQuery(msg)) {
        _answerDisco(msg);
      }
      if (msg.contains('<stream:features') || msg.contains('<features')) {
        if (msg.contains('<mechanism>ANONYMOUS</mechanism>')) {
          _send(
            '<auth mechanism="ANONYMOUS" xmlns="urn:ietf:params:xml:ns:xmpp-sasl"/>',
          );
        } else if (jid.isEmpty) {
          _bindId = _iqId();
          _send(
            '<iq id="$_bindId" type="set" xmlns="jabber:client"><bind xmlns="urn:ietf:params:xml:ns:xmpp-bind"/></iq>',
          );
        } else {
          _sessionId = _iqId();
          _send(
            '<iq id="$_sessionId" type="set" xmlns="jabber:client"><session xmlns="urn:ietf:params:xml:ns:xmpp-session"/></iq>',
          );
          stage = 'Menyiapkan sesi';
          _notify();
        }
        return;
      }
      if (msg.contains('<success')) {
        _send(
          '<open to="$xmppDomain" version="1.0" xmlns="urn:ietf:params:xml:ns:xmpp-framing"/>',
        );
        return;
      }
      if (msg.contains('<stream:error') || msg.contains('<failure')) {
        _fail('Autentikasi Jitsi gagal.');
        return;
      }
      if (msg.contains('type="error"') && msg.contains('jingle')) {
        error = 'Negosiasi media ditolak server.';
        _notify();
      }
      if (_bindId.isNotEmpty && msg.contains(_bindId)) {
        final doc = XmlDocument.parse(msg);
        final jidEl = doc.findAllElements('jid').firstOrNull;
        if (jidEl != null) {
          jid = jidEl.innerText;
          nick = jid.split('@').first.split('-').first;
          _send(
            '<iq id="$_sessionId" type="set" xmlns="jabber:client"><session xmlns="urn:ietf:params:xml:ns:xmpp-session"/></iq>',
          );
          _afterBind();
        }
        return;
      }
      if (msg.contains('<iq') && msg.contains('<services')) {
        _handleIceServices(msg);
      }
      if (_conferenceId.isNotEmpty && msg.contains(_conferenceId)) {
        _handleConference(msg);
        return;
      }
      if (msg.contains('<presence')) {
        _handlePresence(msg);
      }
      if (msg.contains('<jingle') && msg.contains('session-initiate')) {
        unawaited(_handleSessionInitiate(msg));
      }
      if (msg.contains('<jingle') && msg.contains('session-terminate')) {
        hangUp();
      }
    } catch (e) {
      debugPrint('Jitsi stanza error: $e');
    }
  }

  Future<void> _answerDisco(String msg) async {
    try {
      final doc = XmlDocument.parse(msg);
      final id = doc.rootElement.getAttribute('id');
      final from = doc.rootElement.getAttribute('from');
      if (id == null || from == null) return;
      _send(
        xmpp_utils.buildDiscoInfoResult(
          id: id,
          to: from,
          identities: JitsiSdpHelper.jitsiCapsIdentities,
          features: JitsiSdpHelper.jitsiCapsFeatures,
        ),
      );
    } catch (_) {}
  }

  void _afterBind() {
    _discoId = _iqId();
    _send(
      '<iq id="$_discoId" to="$xmppDomain" type="get" xmlns="jabber:client"><services xmlns="urn:xmpp:extdisco:2"/></iq>',
    );
    _conferenceId = _iqId();
    final tokenAttr = token.isNotEmpty ? ' token="$token"' : '';
    _send(
      '<iq id="$_conferenceId" to="focus.$xmppDomain" type="set" xmlns="jabber:client">'
      '<conference machine-uid="${_uuid.v4().replaceAll('-', '')}" room="$_roomJid"$tokenAttr '
      'xmlns="http://jitsi.org/protocol/focus">'
      '<property name="startAudioMuted" value="10"/>'
      '<property name="startVideoMuted" value="10"/>'
      '<property name="rtcstatsEnabled" value="false"/>'
      '<property name="disableP2P" value="true"/>'
      '</conference></iq>',
    );
    stage = 'Meminta ruang panggilan';
    _notify();
  }

  void _handleConference(String msg) {
    if (xmpp_utils.isIqError(msg)) {
      _fail(
          'Server menolak panggilan (${xmpp_utils.extractErrorCondition(msg)}).');
      return;
    }
    final info = xmpp_utils.parseConferenceResponse(msg);
    if (info.focusJid != null) focusJid = info.focusJid!;
    if (info.ready == false) {
      Future.delayed(const Duration(seconds: 1), () {
        if (!closed) {
          final id = _iqId();
          _conferenceId = id;
          _send(
            '<iq id="$id" to="focus.$xmppDomain" type="set" xmlns="jabber:client">'
            '<conference machine-uid="${_uuid.v4().replaceAll('-', '')}" room="$_roomJid"'
            '${token.isNotEmpty ? ' token="$token"' : ''} '
            'xmlns="http://jitsi.org/protocol/focus">'
            '<property name="startAudioMuted" value="10"/>'
            '<property name="startVideoMuted" value="10"/>'
            '<property name="rtcstatsEnabled" value="false"/>'
            '<property name="disableP2P" value="true"/>'
            '</conference></iq>',
          );
        }
      });
      return;
    }
    _sendPresence();
    stage = 'Masuk ke ruang panggilan';
    _notify();
  }

  void _sendPresence() {
    final caps = JitsiSdpHelper.jitsiCapsVer;
    _send(
      '<presence to="$_roomJid/$nick" xmlns="jabber:client">'
      '<x xmlns="http://jabber.org/protocol/muc"/>'
      '<stats-id>${nick.isEmpty ? 'sekitarin' : nick}</stats-id>'
      '<c hash="sha-1" node="https://jitsi.org/jitsi-meet" ver="$caps" xmlns="http://jabber.org/protocol/caps"/>'
      '<features><feature var="https://jitsi.org/meet/e2ee"/></features>'
      '<jitsi_participant_codecList>vp9,h264,vp8,av1</jitsi_participant_codecList>'
      '<nick xmlns="http://jabber.org/protocol/nick">$displayName</nick>'
      '<p2p xmlns="http://jitsi.org/protocol/p2p"><enabled>false</enabled><stun>false</stun><turn>false</turn><backToP2PDelay>0</backToP2PDelay></p2p>'
      '<videomuted>$videoMuted</videomuted>'
      '<audiomuted>$audioMuted</audiomuted>'
      '</presence>',
    );
  }

  void _handlePresence(String msg) {
    try {
      final doc = XmlDocument.parse(msg);
      final from = doc.rootElement.getAttribute('from') ?? '';
      final type = doc.rootElement.getAttribute('type');
      if (type == 'error') {
        _fail(
            'Tidak bisa masuk ruang (${xmpp_utils.extractErrorCondition(msg)}).');
        return;
      }
      if (type == 'unavailable') {
        participants.removeWhere((p) => p.jid == from);
        _notify();
        return;
      }
      final self = doc
          .findAllElements('status',
              namespace: 'http://jabber.org/protocol/muc#user')
          .any((s) => s.getAttribute('code') == '110');
      if (self) {
        stage = 'Menunggu media dari server';
        _notify();
        return;
      }
      if (from.contains('focus') || from.startsWith(focusJid)) {
        if (!participants.any((p) => p.jid == from)) {
          participants.add(JitsiParticipant(jid: from, nickName: 'focus'));
          _notify();
        }
      }
    } catch (_) {}
  }

  void _handleIceServices(String msg) {
    try {
      final doc = XmlDocument.parse(msg);
      final servers = <Map<String, dynamic>>[];
      final seen = <String>{};
      for (final service in doc.findAllElements('service')) {
        final type = service.getAttribute('type')?.toLowerCase();
        final host = service.getAttribute('host');
        if (type == null || host == null || host.isEmpty) continue;
        final port = service.getAttribute('port');
        final suffix = (port == null || port.isEmpty) ? '' : ':$port';
        if (type == 'stun' || type == 'stuns') {
          final url = '${type == 'stuns' ? 'stuns' : 'stun'}:$host$suffix';
          if (seen.add(url)) servers.add({'urls': url});
        } else if (type == 'turn' || type == 'turns') {
          final username = service.getAttribute('username');
          final password = service.getAttribute('password');
          if (username == null || password == null) continue;
          final transport = service.getAttribute('transport')?.toLowerCase();
          final query =
              type == 'turn' && transport != null && transport.isNotEmpty
                  ? '?transport=$transport'
                  : '';
          final url = '$type:$host$suffix$query';
          if (seen.add(url)) {
            servers.add(
                {'urls': url, 'username': username, 'credential': password});
          }
        }
      }
      if (servers.isNotEmpty) _iceServers = servers;
    } catch (_) {}
  }

  Future<void> _setupPeerConnection() async {
    if (pc != null) return;
    final config = <String, dynamic>{
      'sdpSemantics': 'unified-plan',
      'bundlePolicy': 'max-bundle',
      'rtcpMuxPolicy': 'require',
      'iceServers': _iceServers,
    };
    final constraints = <String, dynamic>{
      'mandatory': {'OfferToReceiveAudio': false, 'OfferToReceiveVideo': false},
      'optional': [
        {'DtlsSrtpKeyAgreement': true},
        {'googEchoCancellation': true},
        {'googNoiseSuppression': true},
        {'googAutoGainControl': true},
      ],
    };
    pc = await createPeerConnection(config, constraints);
    final stream = localStream;
    if (stream != null) {
      for (final track in stream.getTracks()) {
        if (track.kind == 'video' && videoMuted) {
          track.enabled = false;
        }
        await pc!.addTrack(track, stream);
      }
    }
    _dataChannel = await pc!.createDataChannel(
      'custom',
      RTCDataChannelInit()
        ..ordered = false
        ..maxRetransmits = 0,
    );
    pc!.onDataChannel = (channel) {
      channel.onMessage = (_) {};
    };
    _dataChannel?.onDataChannelState = (state) {
      if (state == RTCDataChannelState.RTCDataChannelOpen) {
        _onMediaConnected();
      }
    };
    pc!.onIceConnectionState = (state) {
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        _onMediaConnected();
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        _fail('Koneksi media gagal (ICE).');
      }
    };
    pc!.onTrack = (event) async {
      final streams = event.streams;
      if (streams.isEmpty) return;
      final media = streams.first;
      if (event.track.kind != 'video') return;
      final key = media.id;
      if (remoteRenderers.containsKey(key)) return;
      final renderer = RTCVideoRenderer();
      await renderer.initialize();
      renderer.srcObject = media;
      remoteRenderers[key] = renderer;
      remoteRenderer ??= renderer;
      _notify();
    };
  }

  void _onMediaConnected() {
    if (connected) return;
    connected = true;
    error = null;
    stage = '';
    _connectedAt = DateTime.now();
    _connectTimer?.cancel();
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final started = _connectedAt;
      if (started == null) return;
      final seconds = DateTime.now().difference(started).inSeconds;
      final m = (seconds ~/ 60).toString().padLeft(2, '0');
      final s = (seconds % 60).toString().padLeft(2, '0');
      callDuration = '$m:$s';
      _notify();
    });
    Helper.setSpeakerphoneOn(true);
    _notify();
    onConnected?.call();
  }

  Future<void> _handleSessionInitiate(String msg) async {
    try {
      final doc = XmlDocument.parse(msg);
      final from = doc.rootElement.getAttribute('from') ?? focusJid;
      final iqId = doc.rootElement.getAttribute('id');
      if (iqId != null && from.isNotEmpty) {
        _send(
            '<iq id="$iqId" to="$from" type="result" xmlns="jabber:client"/>');
      }
      if (!from.contains('focus') && !from.startsWith(focusJid)) return;
      final jingle = doc.findAllElements('jingle').firstOrNull;
      final sid = jingle?.getAttribute('sid');
      if (sid == null) return;
      if (jingleSid == sid) return;
      jingleSid = sid;
      bridgeSession =
          doc.findAllElements('bridge-session').firstOrNull?.getAttribute('id');
      var index = participants.indexWhere((p) => p.jid == from);
      if (index == -1) {
        participants.add(JitsiParticipant(jid: from, nickName: 'focus'));
        index = participants.length - 1;
      }
      participants[index] =
          participants[index].copyWith(sessionInitiateData: msg, sid: sid);
      stage = 'Menyiapkan media';
      _notify();
      await _setupPeerConnection();
      await _answerJingle(index, msg);
    } catch (e) {
      _fail('Gagal memproses panggilan: $e');
    }
  }

  Future<void> _answerJingle(int idx, String msg) async {
    final peer = pc;
    if (peer == null) return;
    var remoteSdp = await _sdp.parseRemoteSdpFromJitsiXml(idx);
    if (remoteSdp == null) {
      _fail('Server tidak mengirim media.');
      return;
    }
    sdpApplication = await _sdp.jingleToSDP(msg, mediaType: 'data', mid: '2');
    sdpApplication = await _sdp.jingleToSDP(
      msg,
      mediaType: 'data',
      mid: sdpDataMid,
    );
    final doc = XmlDocument.parse(msg);
    String? focusIp;
    String? focusPort;
    for (final c in doc.findAllElements('candidate')) {
      final ip = c.getAttribute('ip') ?? '';
      final port = c.getAttribute('port') ?? '';
      if (!_sdp.isIPv4(ip)) continue;
      if (!_sdp.isPrivateIp(ip)) {
        focusIp = ip;
        focusPort = port;
        break;
      }
    }
    focusIp ??= doc
        .findAllElements('candidate')
        .map((c) => c.getAttribute('ip'))
        .whereType<String>()
        .firstOrNull;
    focusPort ??= doc
        .findAllElements('candidate')
        .map((c) => c.getAttribute('port'))
        .whereType<String>()
        .firstOrNull;
    _sdpMap = await _sdp.extactDataSDP(
      remoteSdp + sdpApplication,
      focusIp ?? '',
      focusPort ?? '',
    );
    await peer.setRemoteDescription(RTCSessionDescription(
      remoteSdp + sdpApplication,
      'offer',
    ));
    var midIndex = 0;
    for (final content in doc.findAllElements('content')) {
      final description = content.findElements('description').firstOrNull;
      final media = description?.getAttribute('media') ??
          content.getAttribute('name') ??
          'audio';
      final localType = media == 'application' ? 'data' : media;
      String? sdpMid;
      for (final entry in _sdpMap.entries) {
        if (entry.key != 'master' && entry.value['type'] == localType) {
          sdpMid = entry.key;
          break;
        }
      }
      sdpMid ??= midIndex.toString();
      final candidates = content.findAllElements('candidate');
      for (final c in candidates) {
        final ip = c.getAttribute('ip');
        final port = c.getAttribute('port');
        final type = c.getAttribute('type');
        final protocol = c.getAttribute('protocol');
        if (ip == null || port == null || type == null || protocol == null) {
          continue;
        }
        final foundation = c.getAttribute('id') ?? '0';
        final component = c.getAttribute('component') ?? '1';
        final priority = c.getAttribute('priority') ?? '0';
        var candidate =
            'candidate:$foundation $component $protocol $priority $ip $port typ $type';
        final raddr = c.getAttribute('rel-addr');
        final rport = c.getAttribute('rel-port');
        if (raddr != null && rport != null) {
          candidate += ' raddr $raddr rport $rport';
        }
        try {
          await peer.addCandidate(RTCIceCandidate(candidate, sdpMid, midIndex));
        } catch (_) {}
      }
      midIndex++;
    }
    final answer = await peer.createAnswer({'voiceActivityDetection': true});
    await peer.setLocalDescription(answer);
    final reordered = await _sdp.reorderSdpForVP8OrVP9(answer.sdp);
    await _sdp.extactTemplateSDP(reordered);
    final xml = await _sdp.sdpToJingleSessionAccept(
      reordered,
      participants[idx].jid,
      jid,
      participants[idx].sid,
      idx,
      false,
    );
    _send(xml);
    stage = 'Menghubungkan media';
    _notify();
  }

  Future<void> toggleAudio() async {
    audioMuted = !audioMuted;
    final stream = localStream;
    if (stream != null) {
      for (final track in stream.getAudioTracks()) {
        track.enabled = !audioMuted;
      }
    }
    _notify();
  }

  Future<void> toggleVideo() async {
    videoMuted = !videoMuted;
    final stream = localStream;
    if (stream != null) {
      final tracks = stream.getVideoTracks();
      if (tracks.isEmpty && !videoMuted) {
        try {
          final media = await navigator.mediaDevices.getUserMedia({
            'audio': false,
            'video': {'facingMode': 'user'},
          });
          final track = media.getVideoTracks().first;
          await pc?.addTrack(track, media);
          localStream = media;
          localRenderer.srcObject = media;
        } catch (_) {
          videoMuted = true;
        }
      }
      for (final track
          in localStream?.getVideoTracks() ?? <MediaStreamTrack>[]) {
        track.enabled = !videoMuted;
      }
    }
    _notify();
  }

  Future<void> switchCamera() async {
    final tracks = localStream?.getVideoTracks() ?? <MediaStreamTrack>[];
    if (tracks.isEmpty) return;
    await Helper.switchCamera(tracks.first);
  }

  Future<void> toggleSpeaker() async {
    speakerOn = !speakerOn;
    await Helper.setSpeakerphoneOn(speakerOn);
    _notify();
  }

  void _notify() => onUpdate?.call();

  void _fail(String message) {
    if (closed) return;
    error = message;
    stage = '';
    _notify();
    onFailed?.call(message);
  }

  void _transportClosed(String reason) {
    if (closed || connected) return;
    _fail('Koneksi ke server terputus.');
  }

  Future<void> hangUp() async {
    if (closed) return;
    closed = true;
    _connectTimer?.cancel();
    _durationTimer?.cancel();
    try {
      _send(
          '<presence type="unavailable" to="$_roomJid/$nick" xmlns="jabber:client"/>');
    } catch (_) {}
    try {
      await _dataChannel?.close();
    } catch (_) {}
    try {
      await pc?.close();
    } catch (_) {}
    pc = null;
    try {
      await _sub?.cancel();
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    for (final renderer in remoteRenderers.values) {
      try {
        await renderer.dispose();
      } catch (_) {}
    }
    remoteRenderers.clear();
    remoteRenderer = null;
    try {
      for (final track in localStream?.getTracks() ?? <MediaStreamTrack>[]) {
        await track.stop();
      }
    } catch (_) {}
    localStream = null;
    try {
      await localRenderer.dispose();
    } catch (_) {}
    onEnded?.call();
    _notify();
  }
}
