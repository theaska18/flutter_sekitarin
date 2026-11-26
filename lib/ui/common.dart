import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

String accountName(Map<String, dynamic>? account) {
  if (account == null) return 'Akun';
  return '${account['display_name'] ?? account['handle'] ?? 'Akun'}';
}

String peerName(Map<String, dynamic> conversation) {
  final peer = conversation['peer'];
  if (peer is Map && peer['display_name'] != null) {
    return '${peer['display_name']}';
  }
  final title = conversation['title'];
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

String formatWhen(dynamic iso) {
  if (iso == null) return '';
  final parsed = DateTime.tryParse('$iso')?.toLocal();
  if (parsed == null) return '';
  return DateFormat('d MMM HH:mm').format(parsed);
}

String messagePreview(Map<String, dynamic>? message) {
  if (message == null) return 'Belum ada pesan';
  if (message['deleted_at'] != null) return 'Pesan dihapus';
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

void showErrorSnack(BuildContext context, Object error) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('$error')),
  );
}
