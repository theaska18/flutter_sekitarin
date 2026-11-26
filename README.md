# Sekitar — Flutter app

Aplikasi mobile iOS/Android untuk backend `cms_sekitarin`. Fitur MVP:

- Registrasi/login email + password dengan token per perangkat.
- Beranda 5 tab: **Chat**, **Peta**, **Post**, **Profil**, **Setelan**.
- Chat direct/grup, kirim teks, read receipt, WebSocket + polling fallback.
- Peta OpenStreetMap: akun usaha dan driver di sekitar, tap marker untuk chat.
- Feed post dari kontak + radius 500 m, like, komentar, dan buat post (1 foto).
- Profil/grid post, ganti akun personal/usaha, tambah akun usaha.
- Katalog & order: lihat layanan akun dari peta, order makanan/jasa/ride,
  pembayaran tunai/transfer, dan alur status (terima → proses → antar →
  selesai/batal).
- Consent lokasi/notifikasi dan feed notifikasi in-app.

## Menjalankan

Butuh Flutter 3.50+ (Dart 3.14).

```bash
cd flutter_sekitarin
flutter pub get
flutter run
```

Default production:

- `API_BASE_URL` = `https://sekitarin.ckamal.com/api/v1`
- `WS_URL` = `wss://sekitarinws.ckamal.com`

Untuk development lokal, override lewat `--dart-define`:

```bash
flutter run \
  --dart-define=API_BASE_URL=http://192.168.1.10:8088/api/v1 \
  --dart-define=WS_URL=ws://192.168.1.10:8090
```

WebSocket default memakai `wss://` (TLS) karena host sudah mendukungnya. Untuk
development lokal yang memakai gateway tanpa TLS, override dengan `ws://`.


Aplikasi memakai HTTP/cleartext untuk development. Sebelum rilis produksi:

- gunakan HTTPS/WSS,
- hapus `android:usesCleartextTraffic="true"` dan `NSAllowsArbitraryLoads` di
  AndroidManifest/Info.plist,
- ganti tile OSM publik dengan tile server/penyedia yang sesuai kebijakan.

## Struktur

```text
lib/
  main.dart                 bootstrap ApiClient, TokenStore, AuthStore, WsClient
  config.dart               API/WS URL dari --dart-define
  core/                     ApiClient, TokenStore, WsClient, ApiException
  state/auth_store.dart     sesi, akun aktif, refresh token
  services/location_service.dart
  ui/auth/                  login & register
  ui/home/                  bottom navigation
  ui/chat/                  daftar chat, chat room, chat baru
  ui/map/                   peta OSM + nearby
  ui/feed/                  feed, komentar, buat post
  ui/profile/               profil, grid, buat akun usaha
  ui/orders/                katalog penyedia, buat order, daftar & detail order
  ui/settings/              akun, consent, logout
  ui/notifications/         feed notifikasi
```

Token akses disimpan di `flutter_secure_storage`; device UUID dan akun aktif di
`SharedPreferences`. Access token diperbarui otomatis sekali lewat
`/auth/refresh` saat server membalas 401.

## Batasan saat ini

- Media post baru satu foto; video belum dipilih dari galeri.
- Push notification belum dihubungkan ke Firebase (backend sudah punya
  `/me/push-token` dan worker FCM). Diperlukan `google-services.json`,
  `GoogleService-Info.plist`, dan paket `firebase_messaging`.
- Belum ada pembuatan grup, pengaturan profil, atau unggah avatar dari app.
- Tarif ride memakai harga layanan dari backend (belum dihitung per jarak).
- Belum ada pilihan multi-dropoff, jadwal order, atau pembayaran gateway.
- Tile OSM memakai server publik untuk development.
