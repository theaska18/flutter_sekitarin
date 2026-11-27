import 'dart:math';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:collection/collection.dart';
import 'package:xml/xml.dart';

import 'jitsi_participant.dart';
import 'package:ed25519_edwards/ed25519_edwards.dart' as ed25519;

class JitsiSdpHelper {
  JitsiSdpHelper(this.session);
  final JitsiSessionView session;
  final uuid = Uuid();
  String formatDuration(int totalSeconds) {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    return [
      if (h > 0) h.toString().padLeft(2, '0'),
      m.toString().padLeft(2, '0'),
      s.toString().padLeft(2, '0')
    ].join(':');
  }

  bool isIPv4(String ip) {
    final reg = RegExp(r'^(\d{1,3}\.){3}\d{1,3}$');
    return reg.hasMatch(ip);
  }

  Map<String, dynamic> extractMessageData(String xmlString) {
    try {
      final document = XmlDocument.parse(xmlString);
      final message = document.rootElement;
      final jsonMessageElement = message.findElements('json-message').first;
      final jsonString = jsonMessageElement.innerText;
      final jsonData = jsonDecode(jsonString);
      final transcriptList = jsonData['transcript'] as List;
      final transcriptText =
          transcriptList.isNotEmpty ? transcriptList.first['text'] : '';
      final participant = jsonData['participant'] as Map<String, dynamic>;
      final isInterim = jsonData['is_interim'] ?? false;
      final confidence = jsonData['confidence'] ?? 0.0;
      final timestamp = jsonData['timestamp'] ?? 0;
      String? occupantId;
      final occupantElement = message.findElements('occupant-id').firstOrNull;
      if (occupantElement != null) {
        occupantId = occupantElement.getAttribute('id');
      }
      final from = message.getAttribute('from') ?? '';
      final to = message.getAttribute('to') ?? '';
      final type = message.getAttribute('type') ?? '';
      return {
        'message_text': transcriptText,
        'participant': {
          'id': participant['id'] ?? '',
          'name': participant['name'] ?? '',
          'email': participant['email'] ?? '',
          'avatar_url': participant['avatar_url'] ?? '',
        },
        'metadata': {
          'confidence': confidence,
          'is_interim': isInterim,
          'timestamp': timestamp,
          'language': jsonData['language'] ?? '',
          'message_id': jsonData['message_id'] ?? '',
          'event': jsonData['event'] ?? '',
          'stability': jsonData['stability'] ?? 0.0,
        },
        'xml_attributes': {
          'from': from,
          'to': to,
          'type': type,
          'occupant_id': occupantId,
        }
      };
    } catch (e) {
      print('Error parsing message: $e');
      return {};
    }
  }

  bool isPrivateIp(String ip) {
    if (ip.startsWith('10.') ||
        ip.startsWith('192.168.') ||
        RegExp(r'^172\.(1[6-9]|2[0-9]|3[0-1])\.').hasMatch(ip)) return true;
    return false;
  }

  static const List<String> jitsiCapsFeatures = [
    'http://jabber.org/protocol/caps',
    'http://jitsi.org/json-encoded-sources',
    'http://jitsi.org/receive-multiple-video-streams',
    'http://jitsi.org/remb',
    'http://jitsi.org/source-name',
    'http://jitsi.org/ssrc-rewriting-1',
    'http://jitsi.org/start-muted-room-metadata',
    'http://jitsi.org/tcc',
    'http://jitsi.org/visitors-1',
    'https://jitsi.org/meet/e2ee',
    'urn:ietf:rfc:4588',
    'urn:xmpp:jingle:1',
    'urn:xmpp:jingle:apps:dtls:0',
    'urn:xmpp:jingle:apps:rtp:1',
    'urn:xmpp:jingle:apps:rtp:audio',
    'urn:xmpp:jingle:apps:rtp:video',
    'urn:xmpp:jingle:transports:dtls-sctp:1',
    'urn:xmpp:jingle:transports:ice-udp:1',
    'urn:xmpp:rayo:client:1',
  ];

  static const List<Map<String, String>> jitsiCapsIdentities = [
    {
      'category': 'client',
      'type': 'web',
      'lang': '',
      'name': 'InfinityOne',
    },
  ];

  static const List<String> _identityCompareKeys = [
    'category',
    'type',
    'lang',
  ];

  static String generateCapsVer({
    List<Map<String, String>> identities = jitsiCapsIdentities,
    List<String> features = jitsiCapsFeatures,
  }) {
    final sortedIdentities = [...identities]..sort((a, b) {
        for (final key in _identityCompareKeys) {
          final result = (a[key] ?? '').compareTo(b[key] ?? '');
          if (result != 0) return result;
        }
        return 0;
      });

    final buffer = StringBuffer();

    for (final identity in sortedIdentities) {
      buffer
        ..write(identity['category'] ?? '')
        ..write('/')
        ..write(identity['type'] ?? '')
        ..write('/')
        ..write(identity['lang'] ?? '')
        ..write('/')
        ..write(identity['name'] ?? '')
        ..write('<');
    }

    for (final feature in [...features]..sort()) {
      buffer
        ..write(feature)
        ..write('<');
    }

    final digest = sha1.convert(utf8.encode(buffer.toString()));
    return base64.encode(digest.bytes);
  }

  static final String jitsiCapsVer = generateCapsVer();

  Future<String> getVer() async => jitsiCapsVer;

  String? getVerFromPresence(String presenceXml) {
    try {
      final document = XmlDocument.parse(presenceXml);

      final cElement = document.findAllElements('c').firstOrNull;

      if (cElement != null) {
        return cElement.getAttribute('ver');
      }
    } catch (e) {
      print("XML parse error: $e");
    }

    return null;
  }

  Future<String?> parseRemoteSdpFromJitsiXml(int idx) async {
    try {
      final document =
          XmlDocument.parse(session.participants[idx].sessionInitiateData);
      final sdpBuffer = StringBuffer();
      sdpBuffer.writeln('v=0');
      final timestamp = DateTime.now().microsecondsSinceEpoch;
      sdpBuffer.writeln('o=- $timestamp 3 IN IP4 0.0.0.0');
      sdpBuffer.writeln('s=-');
      sdpBuffer.writeln('t=0 0');
      sdpBuffer.writeln('a=msid-semantic: WMS mixedmslabel');
      final jingleElement = document.findAllElements('jingle').first;
      session.participants[idx] = session.participants[idx]
          .copyWith(sid: jingleElement.getAttribute('sid')!);
      final Map<String, List<Map<String, dynamic>>> videoParticipantStreams =
          {};
      final Map<String, List<Map<String, dynamic>>> audioParticipantStreams =
          {};
      final List<String> bundleMedia = [];
      final jsonMessage = document.findAllElements('json-message').firstOrNull;
      if (jsonMessage != null) {
        try {
          final jsonData = json.decode(jsonMessage.innerText);
          final sources = jsonData['sources'] as Map<String, dynamic>;
          sources.forEach((participantId, participantData) {
            if (participantData is List) {
              if (participantData.length > 1 &&
                  participantData[2] is List &&
                  (participantData[2] as List).isNotEmpty) {
                final audioList = participantData[2] as List;
                final audioStreamList = <Map<String, dynamic>>[];
                for (final stream in audioList) {
                  if (stream is Map && stream.containsKey('s'))
                    audioStreamList.add({
                      'ssrc': stream['s'].toString(),
                      'cname': stream['n'] ?? '$participantId-a0',
                      'msid': stream['m'] ?? '',
                      'participant': participantId
                    });
                }
                if (audioStreamList.isNotEmpty)
                  audioParticipantStreams[participantId] = audioStreamList;
              }
              if (participantData.isNotEmpty &&
                  participantData[0] is List &&
                  (participantData[0] as List).isNotEmpty) {
                final videoFIDStreams = participantData[1] as List;
                final videoStreams = participantData[0] as List;
                if (videoFIDStreams.length > 0) {
                  for (int i = 0, iLen = videoFIDStreams.length;
                      i < iLen;
                      i++) {
                    bool isVideo = true;
                    final videoFIDStreamList = <Map<String, dynamic>>[];
                    for (int j = 1, jLen = videoFIDStreams[i].length;
                        j < jLen;
                        j++)
                      for (final stream in videoStreams) {
                        if (stream is Map &&
                            stream.containsKey('s') &&
                            videoFIDStreams[i][j] == stream['s']) {
                          videoFIDStreamList.add({
                            'ssrc': stream['s'].toString(),
                            'cname': stream['n'] ?? '$participantId-v0',
                            'msid': stream['m'] ?? '',
                            'participant': participantId
                          });
                          if (stream.containsKey('v')) isVideo = false;
                        }
                      }
                    if (videoFIDStreamList.isNotEmpty)
                      videoParticipantStreams[participantId +
                          '-v' +
                          (isVideo ? '0' : '1')] = videoFIDStreamList;
                  }
                } else {
                  final videoStreams = participantData[0] as List;
                  final videoStreamList = <Map<String, dynamic>>[];
                  for (final stream in videoStreams)
                    if (stream is Map && stream.containsKey('s'))
                      videoStreamList.add({
                        'ssrc': stream['s'].toString(),
                        'cname': stream['n'] ?? '$participantId-v0',
                        'msid': stream['m'] ?? '',
                        'participant': participantId
                      });
                  if (videoStreamList.isNotEmpty)
                    videoParticipantStreams[participantId + '-v0'] =
                        videoStreamList;
                }
              }
            }
          });
        } catch (e) {
          debugPrint("[JITSI]: Error parsing JSON message: $e");
        }
      }
      final contents = document
          .findAllElements('content')
          .where((e) =>
              e.getAttribute('creator') == 'initiator' ||
              e.getAttribute('creator') == 'responder')
          .toList();
      debugPrint(
        '[JITSI] Session-initiate sources: audio=${audioParticipantStreams.length} video=${videoParticipantStreams.length} json=${jsonMessage != null}',
      );
      if (audioParticipantStreams.isNotEmpty ||
          videoParticipantStreams.isNotEmpty) {
        final dataMid =
            audioParticipantStreams.length + videoParticipantStreams.length;
        final hasData = session.sdpApplication.trim().isNotEmpty;
        session.sdpDataMid = dataMid.toString();
        int mediaIndex = 0;
        for (final _ in audioParticipantStreams.entries) {
          bundleMedia.add(mediaIndex.toString());
          mediaIndex++;
        }
        for (final _ in videoParticipantStreams.entries) {
          bundleMedia.add(mediaIndex.toString());
          mediaIndex++;
        }
        sdpBuffer.writeln(
            'a=group:BUNDLE ${bundleMedia.join(' ')}${hasData ? ' $dataMid' : ''}');
        mediaIndex = 0;
        for (final participantEntry in audioParticipantStreams.entries) {
          final participantId = participantEntry.key;
          final audioStream = participantEntry.value;
          final audioContent = contents.firstWhere((e) {
            final desc = e.findElements('description').firstOrNull;
            return desc?.getAttribute('media') == 'audio';
          }, orElse: () => contents.first);
          await _createAudioMediaSectionWithSsrc(
              sdpBuffer, audioContent, mediaIndex, participantId, audioStream);
          mediaIndex++;
        }
        bool isFirst = true;
        for (final participantEntry in videoParticipantStreams.entries) {
          final participantId = participantEntry.key;
          final videoStreams = participantEntry.value;
          final videoContent = contents.firstWhere((e) {
            final desc = e.findElements('description').firstOrNull;
            return desc?.getAttribute('media') == 'video';
          }, orElse: () => contents.first);
          await _createVideoMediaSectionWithSsrc(sdpBuffer, videoContent,
              mediaIndex, participantId, videoStreams, isFirst);
          mediaIndex++;
          isFirst = false;
        }
      } else {
        final audioContent = contents.firstWhereOrNull((e) {
          final desc = e.findElements('description').firstOrNull;
          return desc?.getAttribute('media') == 'audio';
        });
        final videoContent = contents.firstWhereOrNull((e) {
          final desc = e.findElements('description').firstOrNull;
          return desc?.getAttribute('media') == 'video';
        });

        if (audioContent != null || videoContent != null) {
          final mids = <String>[];
          int mediaIndex = 0;
          if (audioContent != null) {
            mids.add('$mediaIndex');
            mediaIndex++;
          }
          if (videoContent != null) {
            mids.add('$mediaIndex');
            mediaIndex++;
          }
          final hasData = session.sdpApplication.trim().isNotEmpty;
          if (hasData) mids.add('$mediaIndex');
          session.sdpDataMid = mediaIndex.toString();
          sdpBuffer.writeln('a=group:BUNDLE ${mids.join(' ')}');

          mediaIndex = 0;
          if (audioContent != null) {
            await _createAudioMediaSectionWithSsrc(
                sdpBuffer, audioContent, mediaIndex, 'jvb', const []);
            mediaIndex++;
          }
          if (videoContent != null) {
            await _createVideoMediaSectionWithSsrc(
                sdpBuffer, videoContent, mediaIndex, 'jvb', const [], true);
          }
        }
      }
      final sdp = sdpBuffer.toString();
      debugPrint("[JITSI]: ✅ Generated SDP without JVB audio $sdp");
      return sdp;
    } catch (e, st) {
      debugPrint("[JITSI]: Error parsing remote SDP: $e\n$st");
      return null;
    }
  }

  Future<void> _createAudioMediaSectionWithSsrc(
      StringBuffer sdpBuffer,
      XmlElement content,
      int mid,
      String participantId,
      List<Map<String, dynamic>> audioStreams) async {
    final description = content.findElements('description').firstOrNull;
    if (description == null) return;
    final payloadIds = description
        .findElements('payload-type')
        .map((p) => p.getAttribute('id'))
        .whereType<String>()
        .join(' ');
    sdpBuffer.writeln('m=audio 9 UDP/TLS/RTP/SAVPF $payloadIds');
    sdpBuffer.writeln('c=IN IP4 0.0.0.0');
    sdpBuffer.writeln('a=mid:$mid');
    if (participantId == 'jvb') {
      sdpBuffer.writeln('a=sendrecv');
    } else
      sdpBuffer.writeln('a=sendonly');
    final transport = content.findElements('transport').firstOrNull;
    if (transport != null) await addTransportToSdp(transport, sdpBuffer);
    if (description.findElements('rtcp-mux').isNotEmpty)
      sdpBuffer.writeln('a=rtcp-mux');
    if (description.findElements('rtcp-rsize').isNotEmpty)
      sdpBuffer.writeln('a=rtcp-rsize');
    for (final ext in description.findElements('rtp-hdrext')) {
      final id = ext.getAttribute('id');
      final uri = ext.getAttribute('uri');
      if (id != null && uri != null) sdpBuffer.writeln('a=extmap:$id $uri');
    }
    if (description.findElements('extmap-allow-mixed').isNotEmpty)
      sdpBuffer.writeln('a=extmap-allow-mixed');
    for (final pt in description.findElements('payload-type')) {
      final id = pt.getAttribute('id');
      final codec = pt.getAttribute('name');
      if (id == null || codec == null) continue;
      final rate = pt.getAttribute('clockrate') ?? '48000';
      final ch = pt.getAttribute('channels') ?? '1';
      sdpBuffer.writeln('a=rtpmap:$id $codec/$rate${ch != '1' ? '/$ch' : ''}');
      final fmtp = pt
          .findElements('parameter')
          .map((p) => '${p.getAttribute('name')}=${p.getAttribute('value')}')
          .where((e) => !e.contains('null'))
          .join(';');
      if (fmtp.isNotEmpty) sdpBuffer.writeln('a=fmtp:$id $fmtp');
      for (final fb in pt.findElements('rtcp-fb')) {
        final type = fb.getAttribute('type');
        if (type != null) {
          final subtype = fb.getAttribute('subtype');
          sdpBuffer.writeln(
              'a=rtcp-fb:$id ${subtype != null ? '$type $subtype' : type}');
        }
      }
    }
    if (audioStreams.isNotEmpty) {
      final first = audioStreams.first;
      final msid = first['msid'];
      if (msid != null && msid.isNotEmpty) sdpBuffer.writeln('a=msid:$msid');
    }
    for (final stream in audioStreams) {
      final ssrc = stream['ssrc'] ?? stream['s'];
      final cname = stream['cname'] ?? stream['n'] ?? 'audio-$participantId';
      final msid = stream['msid'] ?? 'audio-$participantId-msid';
      if (ssrc != null && cname != null) {
        sdpBuffer.writeln('a=ssrc:$ssrc cname:$cname');
        sdpBuffer.writeln('a=ssrc:$ssrc msid:$msid');
      }
    }
  }

  String getInitials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'[\s.]+'))
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1)
      return parts[0].substring(0, parts[0].length >= 2 ? 2 : 1).toUpperCase();

    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  Future<void> _createVideoMediaSectionWithSsrc(
      StringBuffer sdpBuffer,
      XmlElement content,
      int mid,
      String participantId,
      List<Map<String, dynamic>> videoStreams,
      bool isFirst) async {
    final description = content.findElements('description').firstOrNull;
    if (description == null) return;
    participantId = participantId.split("-")[0];
    dynamic priorityPayloads = [];
    // priorityPayloads = ['107', '99'];//h264
    // priorityPayloads = ['101', '97']; //vp9
    priorityPayloads = ['100', '96']; //vp8
    final excludedPayloads = <String>{}; //{'41', '42'};
    final payloadIds = description
        .findElements('payload-type')
        .map((p) => p.getAttribute('id'))
        .whereType<String>()
        .where((id) => !excludedPayloads.contains(id))
        .toList()
      ..sort((a, b) {
        final aInPriority = priorityPayloads.contains(a);
        final bInPriority = priorityPayloads.contains(b);
        if (aInPriority && !bInPriority) return -1;
        if (!aInPriority && bInPriority) return 1;
        return a.compareTo(b);
      });
    sdpBuffer.writeln('m=video 9 UDP/TLS/RTP/SAVPF ${payloadIds.join(' ')}');
    sdpBuffer.writeln('c=IN IP4 0.0.0.0');
    if (isFirst == true) sdpBuffer.writeln('b=AS:400');
    sdpBuffer.writeln('a=mid:$mid');
    if (videoStreams.isNotEmpty) {
      final firstStream = videoStreams.first;
      final msid = firstStream['msid'];
      if (msid != null && msid.isNotEmpty) sdpBuffer.writeln('a=msid:$msid');
    }
    final transport = content.findElements('transport').firstOrNull;
    if (transport != null) await addTransportToSdp(transport, sdpBuffer);
    if (participantId == 'jvb')
      sdpBuffer.writeln('a=sendrecv');
    else
      sdpBuffer.writeln('a=sendonly');
    if (description.findElements('rtcp-mux').isNotEmpty)
      sdpBuffer.writeln('a=rtcp-mux');
    for (final ext in description.findElements('rtp-hdrext')) {
      final id = ext.getAttribute('id');
      final uri = ext.getAttribute('uri');
      if (id != null && uri != null) sdpBuffer.writeln('a=extmap:$id $uri');
    }
    if (description.findElements('extmap-allow-mixed').isNotEmpty)
      sdpBuffer.writeln('a=extmap-allow-mixed');
    for (final pt in description.findElements('payload-type')) {
      final id = pt.getAttribute('id');
      {
        final codecName = pt.getAttribute('name');
        if (id == null || codecName == null) continue;
        final clockrate = pt.getAttribute('clockrate') ?? '8000';
        final channels = pt.getAttribute('channels') ?? '1';
        sdpBuffer.writeln(
            'a=rtpmap:$id $codecName/$clockrate${channels != '1' ? '/$channels' : ''}');
        final fmtpParams = <String>[];
        for (final param in pt.findElements('parameter')) {
          final paramName = param.getAttribute('name') ?? '';
          final paramValue = param.getAttribute('value') ?? '';
          if (paramName.isNotEmpty && paramValue.isNotEmpty)
            fmtpParams.add('$paramName=$paramValue');
        }
        if (fmtpParams.isNotEmpty)
          sdpBuffer.writeln('a=fmtp:$id ${fmtpParams.join(';')}');
        for (final fb in pt.findElements('rtcp-fb')) {
          final type = fb.getAttribute('type');
          if (type != null) {
            final subtype = fb.getAttribute('subtype');
            sdpBuffer.writeln(
                'a=rtcp-fb:$id ${subtype != null ? '$type $subtype' : type}');
          }
        }
      }
    }
    if (videoStreams.length >= 2) {
      final ssrcs =
          videoStreams.map((s) => s['ssrc']).whereType<String>().toList();
      if (ssrcs.length >= 2)
        sdpBuffer.writeln('a=ssrc-group:FID ${ssrcs.join(' ')}');
    }
    for (final stream in videoStreams) {
      final ssrc = stream['ssrc'];
      final cname = stream['cname'];
      final msid = stream['msid'];
      if (ssrc != null && cname != null) {
        sdpBuffer.writeln('a=ssrc:$ssrc cname:$cname');
        if (msid != null) sdpBuffer.writeln('a=ssrc:$ssrc msid:$msid');
      }
    }
  }

  Future<void> addTransportToSdp(
      XmlElement transport, StringBuffer sdpBuffer) async {
    final ufrag = transport.getAttribute('ufrag') ?? '';
    final pwd = transport.getAttribute('pwd') ?? '';
    if (ufrag.isNotEmpty) sdpBuffer.writeln('a=ice-ufrag:$ufrag');
    if (pwd.isNotEmpty) sdpBuffer.writeln('a=ice-pwd:$pwd');
    final fingerprintElem = transport.findElements('fingerprint').firstOrNull;
    if (fingerprintElem != null) {
      final algorithm = fingerprintElem.getAttribute('hash') ?? 'sha-256';
      final value = fingerprintElem.innerText
          .trim()
          .replaceAll(RegExp(r'\s+'), ':')
          .toUpperCase();
      sdpBuffer.writeln('a=fingerprint:$algorithm $value');
      final setupAttr = fingerprintElem.getAttribute('setup') ?? 'actpass';
      sdpBuffer.writeln('a=setup:$setupAttr');
    }
    for (final cand in transport.findElements('candidate')) {
      final foundation = cand.getAttribute('foundation') ?? '1';
      final component = cand.getAttribute('component') ?? '1';
      final protocol = (cand.getAttribute('protocol') ?? 'udp').toLowerCase();
      final priority = cand.getAttribute('priority') ?? '2130706431';
      final ip = cand.getAttribute('ip') ?? '0.0.0.0';
      final port = cand.getAttribute('port') ?? '9';
      final type = cand.getAttribute('type') ?? 'host';
      final relAddr = cand.getAttribute('rel-addr');
      final relPort = cand.getAttribute('rel-port');
      if (relAddr != null && relPort != null) {
        sdpBuffer.writeln(
            'a=candidate:$foundation $component $protocol $priority $ip $port typ $type raddr $relAddr rport $relPort generation 0');
      } else
        sdpBuffer.writeln(
            'a=candidate:$foundation $component $protocol $priority $ip $port typ $type generation 0');
    }
  }

  Future<String> generateRandomAlphaNum(int length) async {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random();
    return List.generate(length, (index) => chars[random.nextInt(chars.length)])
        .join();
  }

  Future<String> jingleToSDP(String jingleXML,
      {String mediaType = 'data', String mid = '2'}) async {
    try {
      final document = XmlDocument.parse(jingleXML);
      final contentElements = document.findAllElements('content');
      final contentElement = contentElements.firstWhere(
          (element) => element.getAttribute('name') == mediaType,
          orElse: () => contentElements.first);
      final transport = contentElement.findElements('transport').first;
      final ufrag = transport.getAttribute('ufrag') ?? '';
      final pwd = transport.getAttribute('pwd') ?? '';
      final fingerprintElement =
          transport.findElements('fingerprint').firstOrNull;
      final fingerprint = fingerprintElement?.innerText.trim() ?? '';
      final candidateElements = transport.findElements('candidate');
      final candidates = candidateElements.map((candidate) {
        return {
          'foundation': candidate.getAttribute('foundation') ?? '1',
          'component': candidate.getAttribute('component') ?? '1',
          'protocol': candidate.getAttribute('protocol') ?? 'udp',
          'priority': _parseIntSafe(candidate.getAttribute('priority')),
          'ip': candidate.getAttribute('ip') ?? '',
          'port': _parseIntSafe(candidate.getAttribute('port')),
          'type': candidate.getAttribute('type') ?? 'host',
          'relAddr': candidate.getAttribute('rel-addr'),
          'relPort': candidate.getAttribute('rel-port'),
          'generation': _parseIntSafe(candidate.getAttribute('generation'))
        };
      }).toList();
      final sctpmap = transport.findElements('sctpmap').firstOrNull;
      final sctpPort = _parseIntSafe(sctpmap?.getAttribute('number'));
      return await _buildSDPString(
          mediaType: mediaType,
          mid: mid,
          ufrag: ufrag,
          pwd: pwd,
          fingerprint: fingerprint,
          candidates: candidates,
          sctpPort: sctpPort);
    } catch (e) {
      debugPrint("[JITSI] Error parsing Jingle XML: $e");
      throw Exception('Failed to parse Jingle XML: $e');
    }
  }

  int _parseIntSafe(String? value) {
    if (value == null) return 0;
    return int.tryParse(value) ?? 0;
  }

  Future<String> _buildSDPString(
      {required String mediaType,
      required String mid,
      required String ufrag,
      required String pwd,
      required String fingerprint,
      required List<Map<String, dynamic>> candidates,
      int sctpPort = 5000,
      int maxMessageSize = 262144}) async {
    final buffer = StringBuffer();
    buffer.writeln('m=application 9 UDP/DTLS/SCTP webrtc-datachannel');
    buffer.writeln('c=IN IP4 0.0.0.0');
    buffer.writeln('a=setup:actpass');
    buffer.writeln('a=mid:$mid');
    buffer.writeln('a=sendrecv');
    buffer.writeln('a=ice-ufrag:$ufrag');
    buffer.writeln('a=ice-pwd:$pwd');
    if (fingerprint.isNotEmpty)
      buffer.writeln('a=fingerprint:sha-256 $fingerprint');
    for (final candidate in candidates) {
      final foundation = candidate['foundation'] ?? '1';
      final component = candidate['component'] ?? '1';
      final protocol = candidate['protocol'] ?? 'udp';
      final priority = candidate['priority'] ?? 0;
      final ip = candidate['ip'] ?? '';
      final port = candidate['port'] ?? 0;
      final type = candidate['type'] ?? 'host';
      final relAddr = candidate['relAddr'];
      final relPort = candidate['relPort'];
      final generation = candidate['generation'];
      String candidateLine =
          'a=candidate:$foundation $component $protocol $priority $ip $port typ $type';
      if (type == 'srflx' && relAddr != null && relPort != null)
        candidateLine += ' raddr $relAddr rport $relPort';
      if (generation != null && generation > 0)
        candidateLine += ' generation $generation';
      buffer.writeln(candidateLine);
    }
    buffer.writeln('a=rtcp-mux');
    buffer.writeln('a=sctp-port:$sctpPort');
    buffer.writeln('a=max-message-size:$maxMessageSize');
    return buffer.toString();
  }

  Future<String> sdpToJingleSessionAccept(String sdp, String initiatorJid,
      String responderJid, String sessionId, int idx, bool initiate) async {
    try {
      final lines = sdp.split('\n');
      final audioPayloads = <String>[];
      final videoPayloads = <String>[];
      String? iceUfrag;
      String? icePwd;
      String? fingerprint;
      String? setup;
      final audioVideoExtensions = <List<Map<String, String>>>[];
      final mediaOrder = <Map<String, String>>[];
      final midToNameMapping = <String, String>{};
      bool inAudio = false;
      bool inVideo = false;
      String? currentMid;
      int currentMediaIndex = -1;
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.startsWith('m=audio')) {
          inAudio = true;
          inVideo = false;
          currentMediaIndex++;
          final parts = trimmed.split(' ');
          if (parts.length > 3) audioPayloads.addAll(parts.sublist(3));
          mediaOrder.add({'name': 'audio', 'media': 'audio'});
          audioVideoExtensions.add([]);
        } else if (trimmed.startsWith('m=video')) {
          inAudio = false;
          inVideo = true;
          currentMediaIndex++;
          final parts = trimmed.split(' ');
          if (parts.length > 3) videoPayloads.addAll(parts.sublist(3));
          mediaOrder.add({'name': 'video', 'media': 'video'});
          audioVideoExtensions.add([]);
        } else if (trimmed.startsWith('a=mid:')) {
          currentMid = trimmed.substring(6);
          if (currentMid.isNotEmpty) {
            if (inAudio) {
              final mediaIndex =
                  mediaOrder.indexWhere((m) => m['media'] == 'audio');
              if (mediaIndex != -1) {
                mediaOrder[mediaIndex]['name'] = currentMid;
                midToNameMapping[currentMid] = 'audio';
              }
            } else if (inVideo) {
              final mediaIndex =
                  mediaOrder.indexWhere((m) => m['media'] == 'video');
              if (mediaIndex != -1) {
                mediaOrder[mediaIndex]['name'] = currentMid;
                midToNameMapping[currentMid] = 'video';
              }
            }
          }
        } else if (trimmed.startsWith('a=ice-ufrag:')) {
          iceUfrag = trimmed.substring(12);
        } else if (trimmed.startsWith('a=ice-pwd:')) {
          icePwd = trimmed.substring(10);
        } else if (trimmed.startsWith('a=fingerprint:sha-256')) {
          fingerprint = trimmed.substring(22);
        } else if (trimmed.startsWith('a=setup:')) {
          setup = trimmed.substring(8);
        } else if (trimmed.startsWith('a=extmap:')) {
          final extParts = trimmed.substring(9).split(' ');
          if (extParts.length >= 2) {
            final id = extParts[0].trim();
            final uri = extParts[1].trim();
            if (inAudio && currentMediaIndex < audioVideoExtensions.length) {
              audioVideoExtensions[currentMediaIndex]
                  .add({'id': id, 'uri': uri});
            } else if (inVideo &&
                currentMediaIndex < audioVideoExtensions.length)
              audioVideoExtensions[currentMediaIndex]
                  .add({'id': id, 'uri': uri});
          }
        }
      }
      final finalSetup = setup ?? 'actpass';
      final incomingNames = <String, List<String>>{
        'audio': [],
        'video': [],
        'data': [],
      };
      try {
        final offerDoc = XmlDocument.parse(
          session.participants[idx].sessionInitiateData,
        );
        for (final content in offerDoc.findAllElements('content')) {
          final desc = content.findElements('description').firstOrNull;
          var media = desc?.getAttribute('media') ?? '';
          if (media == 'application') media = 'data';
          final name = content.getAttribute('name');
          if (name != null && incomingNames.containsKey(media)) {
            incomingNames[media]!.add(name);
          }
        }
      } catch (_) {}
      final usesNumericFormat = mediaOrder.any((m) {
        final name = m['name'];
        return name == '0' || name == '1';
      });
      final finalMediaOrder = <Map<String, String>>[];
      for (int i = 0; i < mediaOrder.length; i++) {
        final m = mediaOrder[i];
        final mediaType = m['media'] ?? 'audio';
        final names = incomingNames[mediaType];
        final offeredName =
            names != null && names.isNotEmpty ? names.removeAt(0) : null;
        final name =
            offeredName ?? (usesNumericFormat ? i.toString() : mediaType);
        finalMediaOrder.add({'name': name, 'media': mediaType});
      }
      final dataContentName = incomingNames['data']?.isNotEmpty == true
          ? incomingNames['data']!.first
          : 'data';
      final hpIdIQSessionAccept = '${uuid.v4()}:sendIQ';
      if (session.participants[idx].jid.contains('focus')) {
        session.participants[idx] = session.participants[idx]
            .copyWith(ufrag: iceUfrag, pwd: icePwd, fingerPrint: fingerprint);
      } else
        session.participants[idx] = session.participants[idx]
            .copyWith(ufrag: iceUfrag, pwd: icePwd, fingerPrint: fingerprint);
      List<String> validContents = [];
      List<String> validGroupNames = [];
      Future<String> buildContent(
          Map<String, String> mediaInfo, int index) async {
        final name = mediaInfo['name']!;
        final mediaType = mediaInfo['media']!;
        final isAudio = mediaType == 'audio';
        final payloads = isAudio ? audioPayloads : videoPayloads;
        List<Map<String, String>> extensions =
            (index < audioVideoExtensions.length
                ? audioVideoExtensions[index]
                : []);

        String ssrcXml = await convertSsrcToXml(
            sdp, responderJid.split('-')[0], mediaType, false, index);
        final ssrcContent = await convertSsrcToXml(
            sdp, responderJid.split('-')[0], mediaType, true, index);
        if (ssrcXml.isEmpty) return "";
        final descriptionAttributes = 'media="$mediaType" ssrc="$ssrcXml"';
        final description =
            '''<description $descriptionAttributes xmlns="urn:xmpp:jingle:apps:rtp:1">${isAudio ? await _buildAudioPayloadTypes(payloads, sdp, index) : await _buildVideoPayloadTypes(sdp, payloads, index)}$ssrcContent<rtcp-mux/>${await _buildRtpHeaderExtensions(extensions)}<extmap-allow-mixed/></description>${await _buildTransportXml(iceUfrag, icePwd, fingerprint, setup: finalSetup)}''';
        validGroupNames.add(name);
        return '''<content creator="${initiate ? 'initiator' : 'responder'}" name="$name" senders="both">$description</content>''';
      }

      final xmlBuffer = StringBuffer();
      xmlBuffer.write(
          '<iq id="$hpIdIQSessionAccept" to="$initiatorJid" type="set" xmlns="jabber:client">');
      xmlBuffer.write(
          '<jingle action="${initiate ? 'session-initiate' : 'session-accept'}" initiator="${initiate ? responderJid : initiatorJid}" ${!initiate ? 'responder="$responderJid"' : ''} sid="$sessionId" xmlns="urn:xmpp:jingle:1">');
      for (int i = 0; i < finalMediaOrder.length; i++) {
        final content = await buildContent(finalMediaOrder[i], i);
        if (content.isNotEmpty) validContents.add(content);
      }
      if (validGroupNames.isNotEmpty) {
        xmlBuffer.write(
            '<group semantics="BUNDLE" xmlns="urn:xmpp:jingle:apps:grouping:0">');
        for (final name in validGroupNames)
          xmlBuffer.write('<content name="$name"/>');
        xmlBuffer.write('<content name="$dataContentName"/>');
        xmlBuffer.write('</group>');
      }
      for (final content in validContents) xmlBuffer.write(content);
      if (session.sdpApplication != '')
        xmlBuffer.write(await sdpToJingleXMLSimple(
          session.sdpApplication,
          contentName: dataContentName,
        ));
      xmlBuffer.write('</jingle></iq>');
      return xmlBuffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    } catch (e) {
      debugPrint("[JITSI]: Error in sdpToJingleSessionAccept2: $e");
      rethrow;
    }
  }

  Future<String> _buildRtpHeaderExtensions(
      List<Map<String, String>> extensions) async {
    final buffer = StringBuffer();
    for (final ext in extensions)
      buffer.write(
          '<rtp-hdrext id="${ext['id']}" uri="${ext['uri']}" xmlns="urn:xmpp:jingle:apps:rtp:rtp-hdrext:0" />');
    return buffer.toString().trim();
  }

  Future<String> _buildVideoPayloadTypes(
      String sdp, List<String> payloads, int mediaIndex) async {
    final buffer = StringBuffer();
    final sdpLines = sdp.split('\n');
    final mediaSections = <List<String>>[];
    List<String>? currentSection;
    for (final line in sdpLines) {
      if (line.startsWith('m=')) {
        if (currentSection != null) mediaSections.add(currentSection);
        currentSection = [line];
      } else if (currentSection != null) currentSection.add(line);
    }
    if (currentSection != null) mediaSections.add(currentSection);
    if (mediaIndex >= mediaSections.length) return '';
    final targetMediaLines = mediaSections[mediaIndex];
    final availablePayloadsInThisMedia = <String>{};
    final mediaLine = targetMediaLines
        .firstWhere((line) => line.startsWith('m='), orElse: () => '');
    if (mediaLine.isNotEmpty) {
      final mediaParts = mediaLine.substring(2).split(' ');
      if (mediaParts.length > 3)
        for (int i = 3; i < mediaParts.length; i++)
          availablePayloadsInThisMedia.add(mediaParts[i].trim());
    }
    final payloadInfo = <String, Map<String, dynamic>>{};
    for (final line in targetMediaLines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('a=rtpmap:')) {
        final parts = trimmed.substring(9).split(' ');
        if (parts.length >= 2) {
          final id = parts[0].trim();
          if (availablePayloadsInThisMedia.contains(id)) {
            final codecInfo = parts[1].trim();
            final codecParts = codecInfo.split('/');
            payloadInfo[id] = {
              'name': codecParts[0],
              'clockrate': codecParts.length > 1 ? codecParts[1] : '90000',
              'channels': codecParts.length > 2 ? codecParts[2] : '1'
            };
          }
        }
      } else if (trimmed.startsWith('a=fmtp:')) {
        final parts = trimmed.substring(7).split(' ');
        if (parts.length >= 2) {
          final id = parts[0].trim();
          final params = parts.sublist(1).join(' ');
          if (availablePayloadsInThisMedia.contains(id)) {
            if (!payloadInfo.containsKey(id)) payloadInfo[id] = {};
            final paramMap = <String, String>{};
            final paramPairs = params.split(';');
            for (final pair in paramPairs) {
              if (pair.contains('=')) {
                final kv = pair.split('=');
                if (kv.length == 2) paramMap[kv[0].trim()] = kv[1].trim();
              }
            }
            payloadInfo[id]!['fmtp'] = paramMap;
          }
        }
      } else if (trimmed.startsWith('a=rtcp-fb:')) {
        final parts = trimmed.substring(10).split(' ');
        if (parts.isNotEmpty) {
          final id = parts[0].trim();
          final type = parts.length > 1 ? parts[1].trim() : '';
          final subtype = parts.length > 2 ? parts[2].trim() : '';
          if (availablePayloadsInThisMedia.contains(id)) {
            if (!payloadInfo.containsKey(id)) payloadInfo[id] = {};
            if (!payloadInfo[id]!.containsKey('rtcp-fb'))
              payloadInfo[id]!['rtcp-fb'] = <Map<String, String>>[];
            (payloadInfo[id]!['rtcp-fb'] as List)
                .add({'type': type, 'subtype': subtype});
          }
        }
      }
    }
    for (final payload in availablePayloadsInThisMedia) {
      final info = payloadInfo[payload];
      if (info == null) continue;
      final name = info['name'] as String? ?? 'unknown';
      final clockrate = info['clockrate'] as String? ?? '90000';
      final channels = info['channels'] as String? ?? '1';
      final fmtp = info['fmtp'] as Map<String, String>?;
      final rtcpFb = info['rtcp-fb'] as List<Map<String, String>>?;
      buffer.write(
          '''<payload-type channels="$channels" clockrate="$clockrate" id="$payload" name="$name">''');
      if (fmtp != null && fmtp.isNotEmpty)
        fmtp.forEach((key, value) {
          buffer.write('<parameter name="$key" value="$value"/>');
        });
      if (rtcpFb != null && rtcpFb.isNotEmpty) {
        for (final fb in rtcpFb) {
          final type = fb['type'] ?? '';
          final subtype = fb['subtype'] ?? '';
          if (subtype.isNotEmpty) {
            buffer.write(
                '<rtcp-fb subtype="$subtype" type="$type" xmlns="urn:xmpp:jingle:apps:rtp:rtcp-fb:0"/>');
          } else
            buffer.write(
                '<rtcp-fb type="$type" xmlns="urn:xmpp:jingle:apps:rtp:rtcp-fb:0"/>');
        }
      } else {
        if (name != 'rtx' && name != 'red' && name != 'ulpfec')
          buffer.write(
              '<rtcp-fb type="transport-cc" xmlns="urn:xmpp:jingle:apps:rtp:rtcp-fb:0"/><rtcp-fb subtype="fir" type="ccm" xmlns="urn:xmpp:jingle:apps:rtp:rtcp-fb:0"/><rtcp-fb type="nack" xmlns="urn:xmpp:jingle:apps:rtp:rtcp-fb:0"/><rtcp-fb subtype="pli" type="nack" xmlns="urn:xmpp:jingle:apps:rtp:rtcp-fb:0"/>');
      }
      buffer.write('</payload-type>');
    }
    return buffer.toString().trim();
  }

  Future<String> _buildTransportXml(
      String? iceUfrag, String? icePwd, String? fingerprint,
      {String setup = 'actpass'}) async {
    if (iceUfrag == null || icePwd == null || fingerprint == null)
      return '<transport xmlns="urn:xmpp:jingle:transports:ice-udp:1"/>';
    return '''<transport pwd="${_xmlAttr(icePwd)}" ufrag="${_xmlAttr(iceUfrag)}" xmlns="urn:xmpp:jingle:transports:ice-udp:1"><fingerprint hash="sha-256" setup="${_xmlAttr(setup)}" xmlns="urn:xmpp:jingle:apps:dtls:0">${_xmlAttr(fingerprint)}</fingerprint></transport>''';
  }

  Future<String> reorderSdpForVP8OrVP9(String? sdp) async {
    if (sdp == null || sdp.isEmpty) return sdp ?? '';
    final lines = sdp.split('\n');
    final buffer = <String>[];
    List<String>? currentSection;
    String? currentMediaType;
    for (final line in lines) {
      if (line.startsWith('m=')) {
        if (currentSection != null && currentMediaType != null) {
          if (currentMediaType == 'video')
            buffer.addAll(await _reorderVideoSection(currentSection));
          else
            buffer.addAll(currentSection);
          buffer.add('');
        }
        currentSection = [line];
        currentMediaType = line.contains('m=video') ? 'video' : 'other';
      } else if (currentSection != null)
        currentSection.add(line);
      else
        buffer.add(line);
    }
    if (currentSection != null && currentMediaType != null) {
      if (currentMediaType == 'video')
        buffer.addAll(await _reorderVideoSection(currentSection));
      else
        buffer.addAll(currentSection);
    }
    return buffer.join('\n');
  }

  List<String> _reorderVideoSection(List<String> section) {
    if (section.isEmpty) return section;
    final mediaLine = section.firstWhere((line) => line.startsWith('m=video'),
        orElse: () => '');
    final vpLines = <String>[];
    final otherLines = <String>[];
    final vpPayloads = <String>{};
    final otherPayloads = <String>{};
    for (final line in section) {
      if (line.startsWith('a=rtpmap:')) {
        final payload = line.split(':')[1].split(' ')[0];
        final codecName = line.toUpperCase();
        // if ((false &&
        //         codecName.contains('VP8/90000')) ||
        //     (!false &&
        //         codecName.contains('VP8/90000'))) {
        if (codecName.contains('H264/90000')) {
          vpPayloads.add(payload);
          vpLines.add(line);
          //    } else if (codecName.contains('AV1/90000')) {
        } else {
          otherPayloads.add(payload);
          otherLines.add(line);
        }
      } else if (line.startsWith('a=fmtp:') || line.startsWith('a=rtcp-fb:')) {
        final payload = line.split(':')[1].split(' ')[0];
        if (vpPayloads.contains(payload))
          vpLines.add(line);
        else
          otherLines.add(line);
      }
    }
    final parts = mediaLine.split(' ');
    if (parts.length >= 4) {
      final newPayloads = [...vpPayloads, ...otherPayloads];
      parts.replaceRange(3, parts.length, newPayloads);
    }
    final result = <String>[parts.join(' ')];
    result.addAll(vpLines);
    result.addAll(otherLines);
    for (final line in section)
      if (!line.startsWith('m=video') &&
          !line.startsWith('a=rtpmap:') &&
          !line.startsWith('a=fmtp:') &&
          !line.startsWith('a=rtcp-fb:')) result.add(line);
    return result;
  }

  Future<String> sdpToJingleXMLSimple(
    String sdp, {
    String contentName = 'data',
  }) async {
    final lines = sdp.split('\n');
    String ufrag = '';
    String pwd = '';
    String fingerprint = '';
    for (final line in lines) {
      if (line.startsWith('a=ice-ufrag:')) {
        ufrag = line.replaceFirst('a=ice-ufrag:', '').trim();
      } else if (line.startsWith('a=ice-pwd:')) {
        pwd = line.replaceFirst('a=ice-pwd:', '').trim();
      } else if (line.startsWith('a=fingerprint:sha-256'))
        fingerprint = line.replaceFirst('a=fingerprint:sha-256', '').trim();
    }
    if (ufrag.isEmpty || pwd.isEmpty || fingerprint.isEmpty)
      throw Exception('Missing required SDP fields');
    return '<content creator="responder" name="$contentName"><transport pwd="$pwd" ufrag="$ufrag" xmlns="urn:xmpp:jingle:transports:ice-udp:1"><sctpmap number="5000" protocol="webrtc-datachannel" streams="0" xmlns="urn:xmpp:jingle:transports:dtls-sctp:1"/><fingerprint hash="sha-256" setup="active" xmlns="urn:xmpp:jingle:apps:dtls:0">${fingerprint.replaceAll(' ', '')}</fingerprint></transport></content>';
  }

  Future<String> convertSsrcToXml(String sdpContent, String participantId,
      String mediaType, bool resultXml, int mediaIndex) async {
    final mediaSections = <String, String>{};
    final lines = sdpContent.split(RegExp(r'\r?\n'));
    String currentType = '';
    int currentIndex = 0;
    final bufferMedia = StringBuffer();
    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('m=')) {
        if (currentType.isNotEmpty) {
          final key = '$currentType-$currentIndex';
          mediaSections[key] = bufferMedia.toString();
          currentIndex++;
          bufferMedia.clear();
        }
        if (line.contains('audio')) {
          currentType = 'audio';
        } else if (line.contains('video')) {
          currentType = 'video';
        } else {
          currentType = '';
          currentIndex = -1;
        }
        bufferMedia.writeln(line);
      } else if (currentType.isNotEmpty) bufferMedia.writeln(line);
    }
    if (currentType.isNotEmpty) {
      final key = '$currentType-$currentIndex';
      mediaSections[key] = bufferMedia.toString();
    }
    final sectionKey = '$mediaType-$mediaIndex';
    final targetSection = mediaSections[sectionKey];
    if (targetSection == null) return '';
    final ssrcMap = <String, Map<String, String>>{};
    final ssrcGroups = <String, List<String>>{};
    final buffer = StringBuffer();
    String firstSsrc = '';
    String defaultStreamId = '';
    String defaultTrackId = '';
    for (final line in targetSection.split(RegExp(r'\r?\n'))) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (trimmed.startsWith('a=msid-semantic:')) {
        final parts = trimmed.substring(16).split(' ');
        if (parts.length >= 2) defaultStreamId = parts[1].trim();
        continue;
      }
      if (trimmed.startsWith('a=msid:')) {
        final msidValue = trimmed.substring(7).trim();
        final msidParts = msidValue.split(' ');
        if (msidParts.length >= 2) {
          defaultStreamId = msidParts[0].trim();
          defaultTrackId = msidParts[1].trim();
        }
        continue;
      }
      if (trimmed.startsWith('a=ssrc:')) {
        final ssrcLine = trimmed.substring(7);
        final parts = ssrcLine.split(RegExp(r'\s+'));
        if (parts.isEmpty) continue;
        final ssrc = parts[0].trim();
        if (firstSsrc.isEmpty) firstSsrc = ssrc;
        ssrcMap.putIfAbsent(ssrc, () => {});
        final restOfLine = ssrcLine.substring(ssrc.length).trim();
        final paramRegex = RegExp(r'([a-zA-Z0-9_\-]+):([^\s]+(?:\s[^\s]+)?)');
        for (final match in paramRegex.allMatches(restOfLine)) {
          final key = match.group(1)!.trim();
          final value = match.group(2)!.trim();
          if (key == 'cname') {
            ssrcMap[ssrc]!['cname'] = value;
          } else if (key == 'msid') {
            final msidParts = value.split(' ');
            if (msidParts.length >= 2) {
              ssrcMap[ssrc]!['streamId'] = msidParts[0].trim();
              ssrcMap[ssrc]!['trackId'] = msidParts[1].trim();
            } else if (msidParts.isNotEmpty)
              ssrcMap[ssrc]!['streamId'] = msidParts[0].trim();
          } else
            ssrcMap[ssrc]![key] = value;
        }
        ssrcMap[ssrc]!
            .putIfAbsent('cname', () => 'user-${ssrc.substring(0, 8)}');
        if (!ssrcMap[ssrc]!.containsKey('streamId') &&
            defaultStreamId.isNotEmpty &&
            defaultTrackId.isNotEmpty) {
          ssrcMap[ssrc]!['streamId'] = defaultStreamId;
          ssrcMap[ssrc]!['trackId'] = defaultTrackId;
        }
      } else if (trimmed.startsWith('a=ssrc-group:')) {
        final parts = trimmed.substring(13).split(' ');
        if (parts.length >= 2) {
          final semantics = parts[0].trim();
          final ssrcs = parts.sublist(1).map((s) => s.trim()).toList();
          ssrcGroups[semantics] = ssrcs;
        }
      }
    }
    if (resultXml) {
      ssrcMap.forEach((ssrc, params) {
        final name = '$participantId-${mediaType == 'audio' ? 'a0' : 'v0'}';
        final videoType = mediaType == 'video' ? ' videoType="camera"' : '';
        buffer.write(
            '<source name="$name" ssrc="$ssrc"$videoType xmlns="urn:xmpp:jingle:apps:rtp:ssma:0">');
        if (params.containsKey('streamId') && params.containsKey('trackId'))
          buffer.write(
              '<parameter name="msid" value="${participantId}-$mediaType-0-1 ${params['trackId']}-1"/>');
        if (params.containsKey('cname'))
          buffer.write('<parameter name="cname" value="${params['cname']}"/>');
        buffer.write('</source>');
      });
      if (mediaType == 'video' && ssrcGroups.isNotEmpty)
        ssrcGroups.forEach((semantics, ssrcs) {
          buffer.write(
              '<ssrc-group semantics="$semantics" xmlns="urn:xmpp:jingle:apps:rtp:ssma:0">');
          for (final ssrc in ssrcs) buffer.write('<source ssrc="$ssrc"/>');
          buffer.write('</ssrc-group>');
        });
      return buffer.toString().trim();
    } else
      return firstSsrc;
  }

  Future<String> _buildAudioPayloadTypes(
      List<String> payloads, String sdp, int mediaIndex) async {
    final buffer = StringBuffer();
    final sdpLines = sdp.split('\n');
    final mediaSections = <List<String>>[];
    List<String>? currentSection;
    for (final line in sdpLines) {
      if (line.startsWith('m=')) {
        if (currentSection != null) mediaSections.add(currentSection);
        currentSection = [line];
      } else if (currentSection != null) currentSection.add(line);
    }
    if (currentSection != null) mediaSections.add(currentSection);
    if (mediaIndex >= mediaSections.length) return '';
    final targetMediaLines = mediaSections[mediaIndex];
    final availablePayloadsInThisMedia = <String>{};
    final mediaLine = targetMediaLines
        .firstWhere((line) => line.startsWith('m='), orElse: () => '');
    if (mediaLine.isNotEmpty) {
      final mediaParts = mediaLine.substring(2).split(' ');
      if (mediaParts.length > 3)
        for (int i = 3; i < mediaParts.length; i++)
          availablePayloadsInThisMedia.add(mediaParts[i].trim());
    }
    final payloadInfo = <String, Map<String, dynamic>>{};
    for (final line in targetMediaLines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('a=rtpmap:')) {
        final parts = trimmed.substring(9).split(' ');
        if (parts.length >= 2) {
          final id = parts[0];
          if (availablePayloadsInThisMedia.contains(id)) {
            final codecParts = parts[1].split('/');
            if (codecParts.length >= 2)
              payloadInfo[id] = {
                'name': codecParts[0],
                'clockrate': codecParts[1],
                'channels': codecParts.length >= 3 ? codecParts[2] : '1'
              };
          }
        }
      } else if (trimmed.startsWith('a=fmtp:')) {
        final parts = trimmed.substring(7).split(' ');
        if (parts.length >= 2) {
          final id = parts[0];
          final params = parts[1];
          if (availablePayloadsInThisMedia.contains(id) &&
              payloadInfo.containsKey(id)) {
            if (id == '63' && params.contains('/')) {
              payloadInfo[id]!['fmtp'] = params;
              payloadInfo[id]!['isRed'] = true;
            } else
              payloadInfo[id]!['fmtp'] = params;
          }
        }
      } else if (trimmed.startsWith('a=rtcp-fb:')) {
        final parts = trimmed.substring(10).split(' ');
        if (parts.length >= 2) {
          final id = parts[0];
          final fbType = parts[1];
          if (availablePayloadsInThisMedia.contains(id) &&
              payloadInfo.containsKey(id)) payloadInfo[id]!['rtcp-fb'] = fbType;
        }
      }
    }
    for (final payload in availablePayloadsInThisMedia) {
      final info = payloadInfo[payload];
      if (info != null) {
        final name = info['name'] ?? 'unknown';
        final clockrate = info['clockrate'] ?? '48000';
        final channels = info['channels'] ?? '1';
        final fmtp = info['fmtp'];
        final rtcpFb = info['rtcp-fb'];
        final isRed = info['isRed'] ?? false;
        buffer.write(
            '''<payload-type id="$payload" name="$name" clockrate="$clockrate" channels="$channels">''');
        if (fmtp != null && fmtp.isNotEmpty) {
          if (isRed) {
            buffer.write('''parameter name="$fmtp"/>''');
          } else {
            final params = fmtp.split(';');
            for (final param in params) {
              final keyValue = param.split('=');
              if (keyValue.length == 2)
                buffer.write(
                    '''<parameter name="${keyValue[0]}" value="${keyValue[1]}"/>''');
            }
          }
        }
        if (rtcpFb != null && rtcpFb.isNotEmpty)
          buffer.write(
              '''<rtcp-fb type="$rtcpFb" xmlns="urn:xmpp:jingle:apps:rtp:rtcp-fb:0"/>''');
        buffer.write('''</payload-type>''');
      }
    }
    return buffer.toString().trim();
  }

  String _xmlAttr(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  Future<Map<String, Map<String, dynamic>>> extactTemplateSDP(
      String? sdp) async {
    Map<String, Map<String, dynamic>> ret = {};
    List<String>? lines = sdp?.split('\n');
    bool isStart = false;
    String statVideo = 'NONE', statAudio = 'NONE', startData = 'NONE';
    Map<String, dynamic> mapAudio = {}, mapVideo = {}, mapData = {};
    if (lines == null) return ret;
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('m=audio')) {
        if (statAudio == 'START') {
          statAudio = 'COMPLETED';
        } else if (statAudio == 'NONE') {
          statAudio = 'START';
          mapAudio['lines'] = [];
          mapAudio['lines'].add(trimmed.replaceAllMapped(
              RegExp(r'^m=(audio|video) 9(?=\s)', multiLine: true),
              (Match m) => 'm=${m[1]} {{port}}'));
          isStart = true;
          if (statVideo == 'START') statVideo = 'COMPLETED';
          if (startData == 'START') startData = 'COMPLETED';
        }
      } else if (trimmed.startsWith('m=video')) {
        if (statVideo == 'START') {
          statVideo = 'COMPLETED';
        } else if (statVideo == 'NONE') {
          statVideo = 'START';
          mapVideo['lines'] = [];
          mapVideo['lines'].add(trimmed.replaceAllMapped(
              RegExp(r'^m=(audio|video) 9(?=\s)', multiLine: true),
              (Match m) => 'm=${m[1]} {{port}}'));
          isStart = true;
          if (statAudio == 'START') statAudio = 'COMPLETED';
          if (startData == 'START') startData = 'COMPLETED';
        }
      } else if (trimmed.startsWith('m=application')) {
        if (startData == 'START')
          startData = 'COMPLETED';
        else if (startData == 'NONE') {
          startData = 'START';
          mapData['lines'] = [];
          mapData['lines'].add(trimmed.replaceAllMapped(
              RegExp(r'^m=(audio|video|application) 9(?=\s)', multiLine: true),
              (Match m) => 'm=${m[1]} {{port}}'));
          isStart = true;
          if (statAudio == 'START') statAudio = 'COMPLETED';
          if (statVideo == 'START') statVideo = 'COMPLETED';
        }
      } else if (isStart == true) {
        if (statAudio == 'START') {
          if (trimmed.contains('c=IN IP4')) {
            mapAudio['lines'].add(trimmed.replaceAll('0.0.0.0', '{{ip}}'));
          } else if (trimmed.contains('ice-ufrag')) {
            mapAudio['lines'].add('a=ice-ufrag:{{ufrag}}');
          } else if (trimmed.contains('ice-pwd')) {
            mapAudio['lines'].add('a=ice-pwd:{{pwd}}');
          } else if (trimmed.contains('a=fingerprint')) {
            mapAudio['lines'].add('a=fingerprint:sha-256 {{fingerprint}}');
          } else if (trimmed.contains('a=mid')) {
            mapAudio['lines'].add('a=mid:{{mid}}');
          } else if (trimmed.contains('a=setup')) {
            mapAudio['lines'].add('a=setup:{{setup}}');
          } else if (trimmed.contains('a=recvonly') ||
              trimmed.contains('a=sendonly') ||
              trimmed.contains('a=sendrecv')) {
            mapAudio['lines'].add('a={{direction}}');
          } else if (trimmed.contains('a=ssrc') ||
              trimmed.contains('a=candidate') ||
              trimmed.contains('ice-options') ||
              trimmed.contains('a=msid') ||
              trimmed.trim() == '') {
          } else
            mapAudio['lines'].add(trimmed);
        } else if (statVideo == 'START') {
          if (trimmed.contains('c=IN IP4')) {
            mapVideo['lines'].add(trimmed.replaceAll('0.0.0.0', '{{ip}}'));
          } else if (trimmed.contains('ice-ufrag')) {
            mapVideo['lines'].add('a=ice-ufrag:{{ufrag}}');
          } else if (trimmed.contains('ice-pwd')) {
            mapVideo['lines'].add('a=ice-pwd:{{pwd}}');
          } else if (trimmed.contains('a=fingerprint')) {
            mapVideo['lines'].add('a=fingerprint:sha-256 {{fingerprint}}');
          } else if (trimmed.contains('a=mid')) {
            mapVideo['lines'].add('a=mid:{{mid}}');
          } else if (trimmed.contains('a=setup')) {
            mapVideo['lines'].add('a=setup:{{setup}}');
          } else if (trimmed.contains('a=recvonly') ||
              trimmed.contains('a=sendonly') ||
              trimmed.contains('a=sendrecv')) {
            mapVideo['lines'].add('a={{direction}}');
          } else if (trimmed.contains('a=ssrc') ||
              trimmed.contains('a=candidate') ||
              trimmed.contains('ice-options') ||
              trimmed.contains('a=msid') ||
              trimmed.trim() == '') {
          } else
            mapVideo['lines'].add(trimmed);
        } else if (startData == 'START') {
          if (trimmed.contains('c=IN IP4')) {
            mapData['lines'].add(trimmed.replaceAll('0.0.0.0', '{{ip}}'));
          } else if (trimmed.contains('ice-ufrag')) {
            mapData['lines'].add('a=ice-ufrag:{{ufrag}}');
          } else if (trimmed.contains('ice-pwd')) {
            mapData['lines'].add('a=ice-pwd:{{pwd}}');
          } else if (trimmed.contains('a=fingerprint')) {
            mapData['lines'].add('a=fingerprint:sha-256 {{fingerprint}}');
          } else if (trimmed.contains('a=mid')) {
            mapData['lines'].add('a=mid:{{mid}}');
          } else if (trimmed.contains('a=setup')) {
            mapData['lines'].add('a=setup:{{setup}}');
          } else if (trimmed.contains('a=recvonly') ||
              trimmed.contains('a=sendonly') ||
              trimmed.contains('a=sendrecv')) {
            mapData['lines'].add('a={{direction}}');
          } else if (trimmed.contains('a=ssrc') ||
              trimmed.contains('a=candidate') ||
              trimmed.contains('ice-options') ||
              trimmed.contains('a=msid') ||
              trimmed.trim() == '') {
          } else
            mapData['lines'].add(trimmed);
        } else if (statVideo == 'COMPLETED' &&
            mapAudio == 'COMPLETED' &&
            startData == 'COMPLETED') {
          break;
        }
      }
    }
    ret['video'] = mapVideo;
    ret['audio'] = mapAudio;
    ret['data'] = mapData;
    return ret;
  }

  Future<String> generateMachineUid() async {
    final rand = Random.secure();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<Map<String, String>> generateJitsiKeys() async {
    final keyPair = ed25519.generateKey();
    final ed25519PublicKey = base64Encode(keyPair.publicKey.bytes);
    final ed25519PrivateKey = base64Encode(keyPair.privateKey.bytes);
    final curve25519PrivateKey =
        await _ed25519ToCurve25519(keyPair.privateKey.bytes);
    final curve25519PublicKey =
        await _generateCurve25519PublicKey(curve25519PrivateKey);
    return {
      'curve25519_public_key': base64Encode(curve25519PublicKey),
      'curve25519_private_key': base64Encode(curve25519PrivateKey),
      'ed25519_public_key': ed25519PublicKey,
      'ed25519_private_key': ed25519PrivateKey
    };
  }

  Future<List<int>> _ed25519ToCurve25519(List<int> ed25519PrivateKey) async {
    return ed25519PrivateKey.sublist(0, 32);
  }

  Future<List<int>> _generateCurve25519PublicKey(List<int> privateKey) async {
    return await _simpleKeyDerivation(privateKey);
  }

  Future<List<int>> _simpleKeyDerivation(List<int> input) async {
    final result = List<int>.filled(32, 0);
    for (int i = 0; i < input.length; i++)
      result[i % 32] = (result[i % 32] + input[i]) % 256;
    return result;
  }

  Future<Map<String, Map<String, dynamic>>> extactDataSDP(
      String? sdp, String ip, String port) async {
    Map<String, Map<String, dynamic>> ret = {};
    List<String>? lines = sdp?.split('\n');
    bool isStart = false, isMove = false;
    Map<String, dynamic> mapData = {};
    Map<String, dynamic> mapMasterData = {};
    mapMasterData['candidates'] = [];
    String lastMid = '';
    String lastNegotiation = '';
    String sid = '';
    if (lines == null) return ret;
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('o=-')) {
        lastNegotiation = trimmed.trim().split(' ')[2];
        sid = trimmed.trim().split(' ')[1];
      } else if (trimmed.startsWith('m=audio') ||
          trimmed.startsWith('m=video') ||
          trimmed.startsWith('m=application')) {
        if (lastMid != '') {
          ret[lastMid] = mapData;
          isMove = true;
        }
        mapData = {};
        if (trimmed.startsWith('m=audio')) {
          mapData['type'] = 'audio';
        } else if (trimmed.startsWith('m=video')) {
          mapData['type'] = 'video';
        } else
          mapData['type'] = 'data';
        mapData['ssrc'] = [];
        isStart = true;
      } else if (isStart == true) {
        if (trimmed.contains('a=mid')) {
          lastMid = trimmed.substring('a=mid:'.length);
        } else if (trimmed.contains('a=msid')) {
          mapData['msid'] = trimmed.substring('a=msid:'.length).trim();
        } else if (trimmed.contains('a=ssrc')) {
          mapData['ssrc'].add(trimmed);
        } else if (trimmed.contains('a=recvonly') ||
            trimmed.contains('a=sendonly') ||
            trimmed.contains('a=sendrecv'))
          mapData['direction'] = trimmed.substring('a='.length).trim();
        if (isMove == false) {
          if (trimmed.contains('ice-ufrag')) {
            mapMasterData['ufrag'] =
                trimmed.substring('a=ice-ufrag:'.length).trim();
          } else if (trimmed.contains('ice-pwd')) {
            mapMasterData['pwd'] = trimmed.substring('a=ice-pwd:'.length);
          } else if (trimmed.contains('a=fingerprint')) {
            mapMasterData['fingerprint'] =
                trimmed.substring('a=fingerprint:sha-256 '.length).trim();
          } else if (trimmed.contains('a=candidate')) {
            mapMasterData['candidates'].add(trimmed);
          } else if (trimmed.contains('a=setup'))
            mapMasterData['setup'] =
                trimmed.substring('a=setup:'.length).trim();
        }
      }
    }
    if (lastMid != '') ret[lastMid] = mapData;
    mapMasterData['lastMid'] = lastMid;
    mapMasterData['lastNegotiation'] = lastNegotiation;
    mapMasterData['ip'] = ip;
    mapMasterData['port'] = port;
    mapMasterData['sid'] = sid;
    ret['master'] = mapMasterData;
    return ret;
  }
}
