import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'theme/app_theme.dart';
import 'consultation_booking_screen.dart';
import 'consultation_history_screen.dart';

/// Halaman utama menu "Konsultasi": pengguna memilih
/// mau membuat janji baru (form) atau melihat riwayat.
/// Simpan file ini di: lib/consultation_hub_screen.dart
class ConsultationHubScreen extends StatelessWidget {
  const ConsultationHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser?.uid ?? 'user_guest';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Konsultasi Desain',
          style: TextStyle(
              color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false, // ini tab, bukan halaman yang di-push
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Mau ngapain hari ini?',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            'Buat janji baru dengan arsitek atau cek konsultasi sebelumnya.',
            style: TextStyle(color: AppColors.textMuted),
          ),
          const SizedBox(height: 24),
          _MenuCard(
            icon: Icons.edit_calendar_outlined,
            title: 'Isi Form Konsultasi',
            subtitle: 'Pilih tanggal, jam, dan ceritakan kebutuhan rumahmu.',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ConsultationBookingScreen(userId: userId),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _MenuCard(
            icon: Icons.history,
            title: 'Riwayat Konsultasi',
            subtitle: 'Lihat status, jadwal, dan pembayaran konsultasimu.',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ConsultationHistoryScreen(userId: userId),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MenuCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: AppColors.primary, size: 26),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 4),
                    Text(subtitle,
                        style: const TextStyle(
                            fontSize: 13, color: AppColors.textMuted)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}