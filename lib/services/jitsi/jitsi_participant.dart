/// Participant state used by the Jitsi/SDP helpers.
class JitsiParticipant {
  JitsiParticipant({
    required this.jid,
    this.nickName = '',
    this.email = '',
    this.avatar = '',
    this.sid = '',
    this.sessionInitiateData = '',
    this.pwd = '',
    this.ufrag = '',
    this.fingerPrint = '',
    this.ssrc = '',
    this.ssrcDesktop = '',
    this.audioMute = true,
    this.videoMute = true,
    this.desktopMute = true,
  });

  final String jid;
  final String nickName;
  final String email;
  final String avatar;
  final String sid;
  final String sessionInitiateData;
  final String pwd;
  final String ufrag;
  final String fingerPrint;
  final String ssrc;
  final String ssrcDesktop;
  final bool audioMute;
  final bool videoMute;
  final bool desktopMute;

  JitsiParticipant copyWith({
    String? jid,
    String? nickName,
    String? email,
    String? avatar,
    String? sid,
    String? sessionInitiateData,
    String? pwd,
    String? ufrag,
    String? fingerPrint,
    String? ssrc,
    String? ssrcDesktop,
    bool? audioMute,
    bool? videoMute,
    bool? desktopMute,
  }) {
    return JitsiParticipant(
      jid: jid ?? this.jid,
      nickName: nickName ?? this.nickName,
      email: email ?? this.email,
      avatar: avatar ?? this.avatar,
      sid: sid ?? this.sid,
      sessionInitiateData: sessionInitiateData ?? this.sessionInitiateData,
      pwd: pwd ?? this.pwd,
      ufrag: ufrag ?? this.ufrag,
      fingerPrint: fingerPrint ?? this.fingerPrint,
      ssrc: ssrc ?? this.ssrc,
      ssrcDesktop: ssrcDesktop ?? this.ssrcDesktop,
      audioMute: audioMute ?? this.audioMute,
      videoMute: videoMute ?? this.videoMute,
      desktopMute: desktopMute ?? this.desktopMute,
    );
  }
}

/// Mutable view of the call session that the SDP helper reads.
abstract class JitsiSessionView {
  List<JitsiParticipant> get participants;
  String get sdpApplication;
  set sdpApplication(String value);
  String get sdpDataMid;
  set sdpDataMid(String value);
}
