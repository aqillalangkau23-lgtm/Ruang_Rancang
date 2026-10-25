import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'consultation_utils.dart';
import 'payment_screen.dart'; // untuk lanjut bayar dari riwayat

typedef _Doc = QueryDocumentSnapshot<Map<String, dynamic>>;

class ConsultationHistoryScreen extends StatefulWidget {
  final String? userId;

  const ConsultationHistoryScreen({Key? key, this.userId}) : super(key: key);

  @override
  State<ConsultationHistoryScreen> createState() =>
      _ConsultationHistoryScreenState();
}

class _StatusStyle {
  final String label;
  final Color bg;
  final Color fg;
  const _StatusStyle(this.label, this.bg, this.fg);
}

class _ConsultationHistoryScreenState extends State<ConsultationHistoryScreen> {
  static const Color primaryDark = Color(0xFF2C3E35);
  late Future<List<_Doc>> _historyFuture;

  @override
  void initState() {
    super.initState();
    _fetchHistory();
  }

  void _fetchHistory() {
    setState(() {
      _historyFuture = FirebaseFirestore.instance
          .collection('consultations')
          .where('userId', isEqualTo: widget.userId)
          .get()
          .then((snapshot) {
        final docs = snapshot.docs.toList();

        // Terbaru di atas (diurutkan di aplikasi, jadi tidak butuh index Firestore)
        docs.sort((a, b) {
          final da = (a.data()['date'] as Timestamp?)?.toDate() ?? DateTime(2000);
          final db = (b.data()['date'] as Timestamp?)?.toDate() ?? DateTime(2000);
          return db.compareTo(da);
        });

        // Bersihkan yang waktu bayarnya sudah habis (set Expired + lepas slot)
        for (final d in docs) {
          if (isPendingExpired(d.data())) expireConsultation(d.id);
        }
        return docs;
      });
    });
  }

  _StatusStyle _statusStyle(String status) {
    switch (status) {
      case ConsultationStatus.paid:
        return _StatusStyle(
            'Lunas', Colors.green.withOpacity(0.12), Colors.green);
      case 'Completed':
      case 'Selesai':
        return _StatusStyle(
            'Selesai', Colors.green.withOpacity(0.12), Colors.green);
      case ConsultationStatus.expired:
        return const _StatusStyle(
            'Kedaluwarsa', Color(0xFFFEE2E2), Color(0xFFB91C1C));
      case 'Cancelled':
        return const _StatusStyle(
            'Dibatalkan', Color(0xFFFEE2E2), Color(0xFFB91C1C));
      default:
        return const _StatusStyle(
            'Menunggu Pembayaran', Color(0xFFFFF7ED), Color(0xFFD97706));
    }
  }

  Future<void> _bukaUrl(String url) async {
    final ok = await launchUrl(Uri.parse(url),
        mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tidak bisa membuka tautan.')),
      );
    }
  }

  /// Kotak info yang muncul setelah konsultasi Lunas:
  /// Online -> tombol gabung meeting, Studio -> alamat + Maps.
  Widget _buildSesiInfo(String method, DateTime date, String timeSlot) {
    final isOnline = method == 'Online';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: isOnline ? _infoOnline(date, timeSlot) : _infoStudio(),
    );
  }

  Widget _infoOnline(DateTime date, String timeSlot) {
    final start = parseSlotStart(date, timeSlot);
    String label = 'Gabung Meeting';
    bool aktif = true;

    if (start != null) {
      final buka =
      start.subtract(const Duration(minutes: kAksesMeetingSebelumMenit));
      final selesai = start.add(const Duration(minutes: kDurasiSesiMenit));
      final now = DateTime.now();
      if (now.isBefore(buka)) {
        aktif = false;
        label = 'Link aktif mulai ${DateFormat('HH:mm').format(buka)}';
      } else if (now.isAfter(selesai)) {
        aktif = false;
        label = 'Sesi telah selesai';
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.videocam_outlined, size: 18, color: primaryDark),
            SizedBox(width: 6),
            Text('Konsultasi Online',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Link meeting aktif $kAksesMeetingSebelumMenit menit sebelum jadwal.',
          style: const TextStyle(fontSize: 12, color: Colors.black54),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryDark,
              disabledBackgroundColor: Colors.grey.shade300,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: aktif ? () => _bukaUrl(kLinkMeeting) : null,
            icon: Icon(Icons.video_call,
                size: 18, color: aktif ? Colors.white : Colors.grey),
            label: Text(label,
                style: TextStyle(
                    color: aktif ? Colors.white : Colors.grey.shade600,
                    fontWeight: FontWeight.bold,
                    fontSize: 13)),
          ),
        ),
      ],
    );
  }

  Widget _infoStudio() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.store_mall_directory_outlined,
                size: 18, color: primaryDark),
            SizedBox(width: 6),
            Text('Datang ke Studio',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          ],
        ),
        const SizedBox(height: 4),
        const Text(kAlamatStudio,
            style: TextStyle(fontSize: 12, color: Colors.black54)),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: primaryDark),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => _bukaUrl(
                'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(kAlamatStudio)}'),
            icon: const Icon(Icons.map_outlined, size: 18, color: primaryDark),
            label: const Text('Buka di Maps',
                style: TextStyle(
                    color: primaryDark,
                    fontWeight: FontWeight.bold,
                    fontSize: 13)),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      appBar: AppBar(
        title: const Text(
          'Riwayat Konsultasi',
          style: TextStyle(
              color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.black87),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: primaryDark),
            onPressed: _fetchHistory,
            tooltip: 'Muat Ulang',
          ),
        ],
      ),
      body: FutureBuilder<List<_Doc>>(
        future: _historyFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: primaryDark),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Terjadi kesalahan: ${snapshot.error}',
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final docs = snapshot.data ?? [];

          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.history_outlined,
                      size: 60, color: Colors.grey),
                  const SizedBox(height: 12),
                  const Text(
                    'Belum ada riwayat konsultasi.',
                    style: TextStyle(color: Colors.grey, fontSize: 15),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _fetchHistory,
                    style:
                    ElevatedButton.styleFrom(backgroundColor: primaryDark),
                    child: const Text('Coba Muat Ulang',
                        style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => _fetchHistory(),
            color: primaryDark,
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: docs.length,
              itemBuilder: (context, index) {
                final doc = docs[index];
                final data = doc.data();

                DateTime date = DateTime.now();
                if (data['date'] != null) {
                  date = (data['date'] as Timestamp).toDate();
                }

                // Kalau Pending tapi waktu bayar habis, tampilkan sebagai Expired
                final status = isPendingExpired(data)
                    ? ConsultationStatus.expired
                    : (data['status'] ?? ConsultationStatus.pending) as String;
                final style = _statusStyle(status);
                final isPending = status == ConsultationStatus.pending;
                final deadline = deadlineOf(data);

                final timeSlot = data['timeSlot'] ?? '-';
                final method = data['method'] ?? 'Online';
                final houseStyle = data['houseStyle'] ?? '-';
                final landArea = data['landArea']?.toString() ?? '0';
                final price = (data['price'] ?? 150000).toDouble();

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.03),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              DateFormat('EEEE, dd MMM yyyy').format(date),
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: style.bg,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                style.label,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: style.fg,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            const Icon(Icons.access_time,
                                size: 16, color: Colors.grey),
                            const SizedBox(width: 6),
                            Text(
                                'Waktu: $timeSlot (${method == 'Online' ? 'Online' : 'Di Studio'})',
                                style: const TextStyle(
                                    fontSize: 13, color: Colors.black87)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(Icons.home_outlined,
                                size: 16, color: Colors.grey),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Gaya: $houseStyle | Luas: $landArea m²',
                                style: const TextStyle(
                                    fontSize: 13, color: Colors.black87),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),

                        // Pending & belum kedaluwarsa: tampilkan batas bayar + tombol bayar
                        if (isPending) ...[
                          if (deadline != null) ...[
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Icon(Icons.timer_outlined,
                                    size: 16, color: Color(0xFFD97706)),
                                const SizedBox(width: 6),
                                Text(
                                  'Bayar sebelum ${DateFormat('HH:mm').format(deadline)}',
                                  style: const TextStyle(
                                      fontSize: 13,
                                      color: Color(0xFFD97706),
                                      fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ],
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8.0),
                            child: Divider(),
                          ),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFD97706),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                padding:
                                const EdgeInsets.symmetric(vertical: 10),
                              ),
                              icon: const Icon(Icons.qr_code_scanner,
                                  size: 18, color: Colors.white),
                              label: const Text(
                                'Bayar Sekarang / Lihat QRIS',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13),
                              ),
                              onPressed: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => PaymentScreen(
                                      consultationId: doc.id,
                                      amount: price,
                                    ),
                                  ),
                                );
                                // Refresh tampilan setelah kembali dari halaman pembayaran
                                _fetchHistory();
                              },
                            ),
                          ),
                        ],

                        // Sudah lunas: tampilkan link meeting / alamat studio
                        if (status == ConsultationStatus.paid)
                          _buildSesiInfo(method, date, timeSlot),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}