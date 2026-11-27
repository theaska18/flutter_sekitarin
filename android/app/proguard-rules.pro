# Jitsi Meet SDK / WebRTC.
-keep class org.jitsi.meet.** { *; }
-keep class org.jitsi.meet.sdk.** { *; }
-keep class org.webrtc.** { *; }
-dontwarn org.webrtc.**
-dontwarn org.jitsi.**

# flutter_callkit_incoming keeps its model keys via reflection.
-keep class com.hiennv.flutter_callkit_incoming.** { *; }
