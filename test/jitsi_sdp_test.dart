import 'package:flutter_test/flutter_test.dart';
import 'package:sekitar_app/services/jitsi/jitsi_participant.dart';
import 'package:sekitar_app/services/jitsi/jitsi_sdp_helper.dart';

class _Session implements JitsiSessionView {
  @override
  final List<JitsiParticipant> participants = [
    JitsiParticipant(
      jid: 'focus@auth.meet.jitsi/focus',
      nickName: 'focus',
      sid: 'sid-1',
      sessionInitiateData: '''
<iq><jingle sid="sid-1">
  <content name="audio"><description media="audio"/></content>
  <content name="video"><description media="video"/></content>
  <content name="data"><description media="application"/></content>
</jingle></iq>
''',
    ),
  ];

  @override
  String sdpApplication = '''
 m=application 9 UDP/DTLS/SCTP webrtc-datachannel
 a=ice-ufrag:remote-data
 a=ice-pwd:remote-data-password
 a=fingerprint:sha-256 00:11:22
 a=setup:actpass
 a=mid:2
 ''';

  @override
  String sdpDataMid = '2';
}

void main() {
  test('Jingle answer retains recvonly video content and per-m-line ICE',
      () async {
    const sdp = '''v=0
    o=- 1 2 IN IP4 127.0.0.1
    s=-
    t=0 0
    a=group:BUNDLE 0 1
    m=audio 9 UDP/TLS/RTP/SAVPF 111
    a=mid:0
    a=ice-ufrag:audioU
    a=ice-pwd:audioPassword
    a=fingerprint:sha-256 11:22:33
    a=setup:active
    a=sendrecv
    a=rtpmap:111 opus/48000/2
    a=msid:stream-a track-a
    a=ssrc:123456 cname:audio-cname
    m=video 9 UDP/TLS/RTP/SAVPF 100
    a=mid:1
    a=ice-ufrag:videoU
    a=ice-pwd:videoPassword
    a=fingerprint:sha-256 11:22:33
    a=setup:active
    a=recvonly
    a=rtpmap:100 VP8/90000
    m=application 9 UDP/DTLS/SCTP webrtc-datachannel
    a=mid:2
    a=ice-ufrag:dataU
    a=ice-pwd:dataPassword
    a=fingerprint:sha-256 11:22:33
    a=setup:active
    ''';
    final helper = JitsiSdpHelper(_Session());
    final result = await helper.sdpToJingleSessionAccept(
      sdp,
      'focus@auth.meet.jitsi/focus',
      '12345678@meet.jitsi/resource',
      'sid-1',
      0,
      false,
    );

    expect(
        result,
        contains(
            '<content creator="responder" name="video" senders="initiator">'));
    expect(result, contains('<content name="video"/>'));
    expect(result, contains('media="video"'));
    expect(result, contains('ufrag="audioU"'));
    expect(result, contains('pwd="audioPassword"'));
    expect(result, contains('ufrag="videoU"'));
    expect(result, contains('pwd="videoPassword"'));
    expect(result, contains('ufrag="dataU"'));
    expect(result, contains('pwd="dataPassword"'));
  });
}
