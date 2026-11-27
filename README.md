# Sekitar — Flutter app

Aplikasi mobile iOS/Android untuk backend `cms_sekitarin`. Fitur MVP:

- Registrasi/login email + password, username publik (mis. `@aska.development`),
  dan konfirmasi password saat daftar.
- Beranda 4 tab: **Chat**, **Peta**, **Post**, **Log Telepon** (placeholder).
  Profil dibuka dari ikon profil di kanan atas header; Setelan dibuka dari
  ikon setelan di halaman Profil.
- Chat direct/grup, buat grup, kelola anggota, ganti nama/foto grup, kirim teks,
  read receipt, penanda **sedang mengetik** (direct & grup), WebSocket + polling
  fallback. Nama pengirim grup diambil dari anggota asli, bukan judul grup.
  Daftar chat juga menampilkan “sedang mengetik…” per percakapan (langsung
  maupun grup). Header chat punya tombol panggilan suara + video (personal)
  dan video saja (grup); fungsinya belum aktif.
  Daftar chat memakai waktu relatif (“time ago”); di dalam chat ada header
  tanggal *sticky* (tanggal + bulan, atau + tahun bila beda tahun) dan jam pesan
  memakai “x menit lalu” hingga 60 menit lalu `HH:mm`.
- Ketuk nama grup untuk membuka **Info grup**; avatar grup selalu ada di pojok
  kanan atas (membuka Info grup) dan ikon peta di sebelahnya membuka **peta
  anggota** yang hanya menampilkan anggota yang menyetujui share lokasi.
- **Bagikan lokasi diatur per grup** dari Info grup, jadi grup lain bisa
  ditolak. Foto grup dapat diganti oleh anggota mana pun; nama grup tetap
  khusus owner. Peta grup terbuka di posisi Anda sendiri dan punya tombol
  kembali ke lokasi saya.
- Logo Sekitarin tampil di header beranda (kiri atas) dan layar login.
- **Kontak**: ikon kontak di topbar (khusus tab Chat) membuka daftar kontak;
  tambah kontak lewat username. Di chat personal yang belum tersimpan sebagai
  kontak, muncul ikon tambah kontak di header.
- Peta OpenStreetMap: memuat area yang sedang dilihat (pan/zoom, debounce
  400 ms), akun freeze selalu tampil; akun realtime/driver muncul setelah
  “Bagikan lokasi” di Setelan aktif. Di bawah zoom 14.5 data tidak dimuat agar
  tidak menarik seluruh area. Update otomatis tiap 10 detik, marker “Akunmu”
  untuk akun sendiri, tap marker untuk chat/pesan. Marker pengemudi (mobil,
  motor, kurir) memakai ikon kendaraan tanpa lingkaran. Peta memakai tile OSM
  terang untuk sementara, termasuk saat mode gelap. Ikon profil di header
  menampilkan foto akun aktif; akun non-personal diberi badge ikon tipe akun
  (mis. mobil untuk driver) di pojok kanan bawah.
- Akun usaha: pilih **Realtime GPS** (lokasi diperbarui tiap 15 detik selama app
  aktif) atau **freeze** dengan titik yang dipilih di peta. Status
  **Aktif/Tutup** juga diatur di layar Pengaturan usaha dan tampil di peta.
  Foto, nama, dan username bisnis dapat diubah; username bisnis terpisah dari
  username personal dan tidak bisa dipakai untuk login.
- Feed post dari kontak + radius 2 km, label **Kontak / Sekitar (jarak) /
  Akunmu**, like, komentar, buat post, serta menu tiga titik untuk edit/hapus
  post milik sendiri. Detail post bisa dibuka dari feed atau grid profil, dengan
  daftar komentator dan aksi edit/hapus. Lokasi dipakai hanya untuk memfilter
  post sekitar (tidak dibagikan ke pengguna lain) dan diminta saat feed dimuat.
  Bila tidak ada akun yang berbagi lokasi di sekitar, feed menampilkan post
  publik 7 hari terakhir dengan label **Terbaru**. Post dengan lokasi akun
  diketahui menampilkan jarak, mis. **850 m dari kamu** — termasuk jika akun
  tersebut kontak atau akun sendiri. Post **Terbaru** tidak punya jarak karena
  lokasi akunnya tidak diketahui.
- Profil/grid post, edit nama/username, **ganti foto profil** (galeri/kamera),
  ganti password, dan **Pengaturan usaha** (aktif/tutup, realtime/freeze,
  titik peta). Tambah akun usaha ada di Setelan. Foto/nama pembuat post dan
  komentator bisa diketuk untuk membuka profil akun tersebut beserta grid
  post-nya; jika akun itu akun aktif sendiri, yang terbuka adalah halaman
  Profil yang sudah ada.
- Setelan (dibuka dari **Profil → ikon setelan**) menampilkan daftar akun
  dengan badge **Aktif/Nonaktif**, ikon GPS
  untuk akun live GPS, waktu berlaku aktif, tombol pengaturan usaha, dan aksi
  dalam layout ringkas. Akun bisnis aktif otomatis berakhir setelah 24 jam dan
  harus diaktifkan ulang dari Setelan.
- Katalog & order: lihat layanan akun dari peta, order makanan/jasa/ride,
  pembayaran tunai/transfer, dan alur status (terima → proses → antar →
  selesai/batal).
- Notifikasi in-app: badge chat hilang saat tab Chat dibuka, dan daftar chat
  menandai percakapan yang belum dibaca (teks tebal + badge jumlah).

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


## Build APK untuk uji perangkat

Dengan Android SDK + JDK 17 terpasang:

```bash
flutter build apk --debug
```

Hasil: `build/app/outputs/flutter-apk/app-debug.apk`. Kirim ke HP Android dan
pasang (izinkan “Install unknown apps”), atau lewat USB:

```bash
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

Debug APK memakai default production (`https://sekitarin.ckamal.com/api/v1`,
`wss://sekitarinws.ckamal.com`). Untuk mengarahkan ke server lokal saat build:

```bash
flutter build apk --debug \
  --dart-define=API_BASE_URL=http://192.168.1.10:8088/api/v1 \
  --dart-define=WS_URL=ws://192.168.1.10:8090
```

Aplikasi memakai HTTP/cleartext untuk development. Sebelum rilis produksi:

- gunakan HTTPS/WSS,
- hapus `android:usesCleartextTraffic="true"` dan `NSAllowsArbitraryLoads` di
  AndroidManifest/Info.plist,
- ganti tile OSM publik dengan tile server/penyedia yang sesuai kebijakan.

## Update aplikasi

Buka **Profil → Setelan → Cek update**. Aplikasi membandingkan versi terpasang
dengan `GET /api/v1/app/latest`; jika lebih baru, APK diunduh dari
`/api/v1/app/download` dengan progres langsung di baris **Cek update**
(persentase, MB terunduh/total, tombol Batal). Setelah selesai, installer
Android dibuka (izin `REQUEST_INSTALL_PACKAGES` sudah diminta di manifest).
APK yang sudah terunduh disimpan per versi; jika installer gagal/tidak sengaja
ditutup, tombol **Pasang** membuka ulang installer tanpa mengunduh lagi.

Proses rilis (wajib untuk setiap perubahan): lihat `AGENTS.md` dan
`../cms_sekitarin/AGENTS.md`.

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
  ui/chat/                  daftar chat, chat room, chat baru, buat grup, info grup
  ui/contacts/              tambah kontak lewat username
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
- Tema terang/gelap mengikuti sistem; tidak ada pilihan tema manual.
- Realtime GPS berjalan saat aplikasi aktif (foreground); background location
  perlu foreground service/plugin tambahan.
- Tarif ride memakai harga layanan dari backend (belum dihitung per jarak).
- Belum ada pilihan multi-dropoff, jadwal order, atau pembayaran gateway.
- Tile OSM memakai server publik untuk development.
