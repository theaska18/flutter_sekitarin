import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sekitar_app/ui/common.dart';

void main() {
  test('typeIcon maps account types', () {
    expect(typeIcon('driver_motor'), Icons.two_wheeler);
    expect(typeIcon('warung'), Icons.storefront);
    expect(typeIcon('unknown'), Icons.person);
  });

  test('messagePreview handles media and deleted messages', () {
    expect(messagePreview({'type': 'image'}), '📷 Foto');
    expect(messagePreview({'type': 'text', 'body': 'Halo'}), 'Halo');
    expect(messagePreview({'deleted_at': '2026-01-01'}), 'Pesan dihapus');
  });

  test('order helpers map account types and statuses', () {
    expect(orderTypeForAccount('warung'), 'food');
    expect(orderTypeForAccount('driver_motor'), 'ride');
    expect(orderTypeForAccount('tambal_ban'), 'service');
    expect(orderStatusLabel('in_progress'), 'Diproses');
    expect(orderStatusLabel('cancelled'), 'Dibatalkan');
    expect(orderTypeLabel('ride'), 'Ojek / Ride');
  });
}
