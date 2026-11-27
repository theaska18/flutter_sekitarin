class ConferenceResponseInfo {
  final bool? ready;
  final String? focusJid;

  const ConferenceResponseInfo({this.ready, this.focusJid});
}

bool isIqError(String msg) =>
    RegExp(r'''\btype\s*=\s*["']error["']''').hasMatch(msg);

bool isIqGet(String msg) =>
    RegExp(r'''\btype\s*=\s*["']get["']''').hasMatch(msg);

bool isDiscoInfoQuery(String msg) =>
    isIqGet(msg) && msg.contains('http://jabber.org/protocol/disco#info');

bool isPingQuery(String msg) => isIqGet(msg) && msg.contains('urn:xmpp:ping');

String extractIqFrom(String msg) =>
    RegExp(r'''\bfrom\s*=\s*["']([^"']+)["']''').firstMatch(msg)?.group(1) ??
    '';

bool isFocusAddress(String address) =>
    address.contains('focus') || address.startsWith('focus.');

bool isOptionalServiceIqError(String msg) {
  if (!isIqError(msg) || msg.contains('jingle')) return false;
  final from = extractIqFrom(msg);
  return from.isNotEmpty && !isFocusAddress(from);
}

String extractErrorCondition(String msg) {
  final block =
      RegExp(r'<error\b[^>]*>(.*?)</error>', dotAll: true).firstMatch(msg);
  if (block == null) return '';
  final condition = RegExp(r'<([A-Za-z0-9:_-]+)(?:\s[^>]*)?\s*/>')
      .firstMatch(block.group(1)!);
  return condition?.group(1) ?? '';
}

ConferenceResponseInfo parseConferenceResponse(String msg) {
  final readyMatch = RegExp(
    r'''<conference\b[^>]*\bready\s*=\s*["']([^"']+)["']''',
  ).firstMatch(msg);
  final focusMatch = RegExp(r'<focusjid>([^<]+)</focusjid>').firstMatch(msg);
  final focusJid = focusMatch?.group(1)?.trim();
  return ConferenceResponseInfo(
    ready: readyMatch == null
        ? null
        : readyMatch.group(1)!.toLowerCase() == 'true',
    focusJid: (focusJid == null || focusJid.isEmpty) ? null : focusJid,
  );
}

String buildDiscoInfoResult({
  required String id,
  required String to,
  String? node,
  required List<Map<String, String>> identities,
  required List<String> features,
}) {
  final nodeAttr = (node == null || node.isEmpty)
      ? ''
      : ' node="${escapeXmlAttribute(node)}"';
  final identityXml = identities
      .map(
        (identity) =>
            '<identity category="${escapeXmlAttribute(identity['category'] ?? '')}" '
            'type="${escapeXmlAttribute(identity['type'] ?? '')}" '
            'name="${escapeXmlAttribute(identity['name'] ?? '')}"/>',
      )
      .join();
  final featureXml = features
      .map((feature) => '<feature var="${escapeXmlAttribute(feature)}"/>')
      .join();
  return '<iq id="${escapeXmlAttribute(id)}" to="${escapeXmlAttribute(to)}" '
      'type="result" xmlns="jabber:client">'
      '<query xmlns="http://jabber.org/protocol/disco#info"$nodeAttr>'
      '$identityXml$featureXml</query></iq>';
}

String buildJingleDecline({
  required String id,
  required String to,
  required String sid,
}) =>
    '<iq id="${escapeXmlAttribute(id)}" to="${escapeXmlAttribute(to)}" '
    'type="set" xmlns="jabber:client">'
    '<jingle action="session-terminate" '
    'initiator="${escapeXmlAttribute(to)}" '
    'sid="${escapeXmlAttribute(sid)}" xmlns="urn:xmpp:jingle:1">'
    '<reason><decline/><text>P2P disabled</text></reason></jingle></iq>';

String escapeXmlAttribute(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

String buildStreamOpen(String domain) =>
    '<open to="$domain" version="1.0" xmlns="urn:ietf:params:xml:ns:xmpp-framing"/>';

String buildAnonymousAuth() =>
    '<auth mechanism="ANONYMOUS" xmlns="urn:ietf:params:xml:ns:xmpp-sasl"/>';

String buildBindIq() =>
    '<iq id="_bind_auth_2" type="set" xmlns="jabber:client">'
    '<bind xmlns="urn:ietf:params:xml:ns:xmpp-bind"/></iq>';

String buildSessionIq() =>
    '<iq id="_session_auth_2" type="set" xmlns="jabber:client">'
    '<session xmlns="urn:ietf:params:xml:ns:xmpp-session"/></iq>';

String buildSmEnable() => '<enable resume="true" xmlns="urn:xmpp:sm:3"/>';

String buildExtdisco2({required String id, required String domain}) =>
    '<iq id="$id" to="$domain" type="get" xmlns="jabber:client">'
    '<services xmlns="urn:xmpp:extdisco:2"/></iq>';

String buildExtdisco1({required String id, required String domain}) =>
    '<iq id="$id" to="$domain" type="get" xmlns="jabber:client">'
    '<services xmlns="urn:xmpp:extdisco:1"/></iq>';

String buildDomainDisco({
  required String id,
  required String from,
  required String domain,
}) =>
    '<iq from="$from" id="$id" to="$domain" type="get" xmlns="jabber:client">'
    '<query xmlns="http://jabber.org/protocol/disco#info"/></iq>';

String buildBreakoutDisco({
  required String id,
  required String from,
  required String domain,
}) =>
    '<iq from="$from" id="$id" to="breakout.$domain" type="get" '
    'xmlns="jabber:client">'
    '<query node="breakout_rooms" '
    'xmlns="http://jabber.org/protocol/disco#info"/></iq>';

String buildLobbyDisco({
  required String id,
  required String from,
  required String domain,
}) =>
    '<iq from="$from" id="$id" to="lobby.$domain" type="get" '
    'xmlns="jabber:client">'
    '<query node="lobbyrooms" '
    'xmlns="http://jabber.org/protocol/disco#info"/></iq>';

String buildRoomDisco({
  required String id,
  required String room,
  required String domain,
}) =>
    '<iq id="$id" to="$room@muc.$domain" type="get" xmlns="jabber:client">'
    '<query xmlns="http://jabber.org/protocol/disco#info"/></iq>';

String buildPing({required String id, required String to}) =>
    '<iq id="$id" to="$to" type="get" xmlns="jabber:client">'
    '<ping xmlns="urn:xmpp:ping"/></iq>';

String buildPingResult({required String id, required String to}) =>
    '<iq id="${escapeXmlAttribute(id)}" to="${escapeXmlAttribute(to)}" '
    'type="result" xmlns="jabber:client"/>';
