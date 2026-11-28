import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

String accountName(Map<String, dynamic>? account) {
  if (account == null) return 'Akun';
  return '${account['display_name'] ?? account['handle'] ?? 'Akun'}';
}

String peerName(Map<String, dynamic> conversation) {
  final title = conversation['title'];
  if (conversation['type'] == 'group' && title != null && '$title'.isNotEmpty) {
    return '$title';
  }
  final peer = conversation['peer'];
  if (peer is Map && peer['display_name'] != null) {
    return '${peer['display_name']}';
  }
  if (title != null && '$title'.isNotEmpty) return '$title';
  return 'Percakapan';
}

IconData typeIcon(String? type) {
  switch (type) {
    case 'warung':
      return Icons.storefront;
    case 'restoran':
      return Icons.restaurant;
    case 'tambal_ban':
      return Icons.build;
    case 'driver_motor':
      return Icons.two_wheeler;
    case 'driver_mobil':
      return Icons.directions_car;
    case 'kurir_makanan':
      return Icons.delivery_dining;
    case 'terapis':
      return Icons.spa;
    case 'jasa_umum':
      return Icons.handyman;
    default:
      return Icons.person;
  }
}

Color typeColor(String? type) {
  switch (type) {
    case 'driver_motor':
    case 'driver_mobil':
      return const Color(0xFF1D4ED8);
    case 'warung':
    case 'restoran':
      return const Color(0xFFB45309);
    case 'tambal_ban':
    case 'jasa_umum':
      return const Color(0xFF7C3AED);
    case 'terapis':
      return const Color(0xFFBE185D);
    case 'kurir_makanan':
      return const Color(0xFF047857);
    default:
      return const Color(0xFF0F766E);
  }
}

String timeRemaining(dynamic iso) {
  if (iso == null) return '';
  final parsed = DateTime.tryParse('$iso')?.toLocal();
  if (parsed == null) return '';
  final diff = parsed.difference(DateTime.now());
  if (diff.isNegative || diff.inSeconds <= 0) return 'Kedaluwarsa';
  final hours = diff.inHours.toString().padLeft(2, '0');
  final minutes = (diff.inMinutes % 60).toString().padLeft(2, '0');
  final seconds = (diff.inSeconds % 60).toString().padLeft(2, '0');
  return 'Sisa $hours:$minutes:$seconds';
}

String timeAgo(dynamic iso) {
  if (iso == null) return '';
  final parsed = DateTime.tryParse('$iso')?.toLocal();
  if (parsed == null) return '';
  final diff = DateTime.now().difference(parsed);
  if (diff.isNegative || diff.inMinutes < 1) return 'baru saja';
  if (diff.inMinutes < 60) return '${diff.inMinutes} menit lalu';
  if (diff.inHours < 24) return '${diff.inHours} jam lalu';
  if (diff.inDays < 7) return '${diff.inDays} hari lalu';
  if (diff.inDays < 30) return '${diff.inDays ~/ 7} minggu lalu';
  if (diff.inDays < 365) return '${diff.inDays ~/ 30} bulan lalu';
  return '${diff.inDays ~/ 365} tahun lalu';
}

const _indonesianMonths = [
  'Januari',
  'Februari',
  'Maret',
  'April',
  'Mei',
  'Juni',
  'Juli',
  'Agustus',
  'September',
  'Oktober',
  'November',
  'Desember',
];

/// Sticky chat date label: "27 November", or "27 November 2025" when the
/// date is not in the current year.
String chatDateLabel(dynamic iso) {
  final parsed = DateTime.tryParse('$iso')?.toLocal();
  if (parsed == null) return '';
  final month = _indonesianMonths[parsed.month - 1];
  final label = '${parsed.day} $month';
  return parsed.year == DateTime.now().year ? label : '$label ${parsed.year}';
}

/// Message time: relative while under 60 minutes, then the wall clock
/// ("02:30"). The date is provided by the sticky day header.
String chatMessageTime(dynamic iso) {
  if (iso == null) return '';
  final parsed = DateTime.tryParse('$iso')?.toLocal();
  if (parsed == null) return '';
  final diff = DateTime.now().difference(parsed);
  if (!diff.isNegative && diff.inMinutes < 60) return timeAgo(iso);
  return DateFormat('HH:mm').format(parsed);
}

/// Human-readable distance for nearby posts: "850 m" or "1,2 km".
String formatDistance(dynamic meters) {
  final value = meters is num ? meters.toDouble() : double.tryParse('$meters');
  if (value == null || value <= 0) return '';
  if (value >= 1000) {
    return '${(value / 1000).toStringAsFixed(1).replaceAll('.', ',')} km';
  }
  return '${value.round()} m';
}

String formatWhen(dynamic iso) {
  if (iso == null) return '';
  final parsed = DateTime.tryParse('$iso')?.toLocal();
  if (parsed == null) return '';
  return DateFormat('d MMM HH:mm').format(parsed);
}

String messagePreview(Map<String, dynamic>? message) {
  if (message == null) return 'Belum ada pesan';
  if (message['deleted_at'] != null) return 'Pesan ini dihapus';
  final type = '${message['type'] ?? 'text'}';
  switch (type) {
    case 'image':
      return '📷 Foto';
    case 'file':
      return '📎 File';
    case 'audio':
      return '🎙️ Voice note';
    case 'location':
      return '📍 Lokasi';
    default:
      return '${message['body'] ?? ''}';
  }
}

String rupiah(num value) {
  final format = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );
  try {
    return format.format(value);
  } catch (_) {
    return 'Rp ${value.toStringAsFixed(0)}';
  }
}

String normalizeUsername(String value) {
  return value.trim().toLowerCase().replaceFirst(RegExp(r'^@+'), '');
}

bool validUsername(String value) {
  return RegExp(r'^[a-z0-9._]{3,40}$').hasMatch(normalizeUsername(value));
}

String orderStatusLabel(String? status) {
  switch (status) {
    case 'pending':
      return 'Menunggu';
    case 'accepted':
      return 'Diterima';
    case 'in_progress':
      return 'Diproses';
    case 'delivering':
      return 'Diantar';
    case 'completed':
      return 'Selesai';
    case 'cancelled':
      return 'Dibatalkan';
    default:
      return 'Status';
  }
}

Color orderStatusColor(String? status) {
  switch (status) {
    case 'pending':
      return const Color(0xFFB45309);
    case 'accepted':
      return const Color(0xFF1D4ED8);
    case 'in_progress':
    case 'delivering':
      return const Color(0xFF7C3AED);
    case 'completed':
      return const Color(0xFF047857);
    case 'cancelled':
      return const Color(0xFFB91C1C);
    default:
      return const Color(0xFF475569);
  }
}

String orderTypeLabel(String? type) {
  switch (type) {
    case 'food':
      return 'Makanan';
    case 'ride':
      return 'Ojek / Ride';
    case 'service':
      return 'Jasa';
    default:
      return 'Order';
  }
}

String orderTypeForAccount(String? typeCode) {
  switch (typeCode) {
    case 'warung':
    case 'restoran':
      return 'food';
    case 'driver_motor':
    case 'driver_mobil':
    case 'kurir_makanan':
      return 'ride';
    default:
      return 'service';
  }
}

void showErrorSnack(BuildContext context, Object error) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('$error')),
  );
}

/// Centers page content and caps its width on tablets so lists keep a
/// comfortable reading width in portrait and landscape.
class ReadableWidth extends StatelessWidget {
  const ReadableWidth({super.key, required this.child, this.maxWidth = 720});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
