import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'consultation_history_screen.dart';
import 'consultation_utils.dart';

class PaymentScreen extends StatefulWidget {
  final String consultationId;
  final double amount;

  const PaymentScreen({
    Key? key,
    required this.consultationId,
    this.amount = 150000.0,
  }) : super(key: key);

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  static const Color primaryDark = Color(0xFF2C3E35);

  Timer? _timer;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _subscription;

  DateTime? _deadline; // dibaca dari Firestore, bukan timer lokal
  Duration _timeLeft = Duration.zero;
  bool _loaded = false;
  bool _isSuccess = false;
  bool _isExpired = false;
  bool _expireTriggered = false;

  /// QR "pura-pura": isinya unik per transaksi (order id + nominal).
  String get _qrImageUrl {
    final payload =
        'RUANGRANCANG-PAY|${widget.consultationId}|${widget.amount.toStringAsFixed(0)}';
    return 'https://api.qrserver.com/v1/create-qr-code/?size=250x250&data=${Uri.encodeComponent(payload)}';
  }

  @override
  void initState() {
    super.initState();
    _listenToConsultation();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _subscription?.cancel();
    super.dispose();
  }

  // Dengar perubahan data konsultasi secara real-time
  void _listenToConsultation() {
    _subscription = FirebaseFirestore.instance
        .collection('consultations')
        .doc(widget.consultationId)
        .snapshots()
        .listen((snapshot) {
      final data = snapshot.data();
      if (data == null || !mounted) return;

      _deadline = deadlineOf(data);
      final status = data['status'];

      if (status == ConsultationStatus.paid && !_isSuccess) {
        _isSuccess = true;
        _showSuccessDialog();
      }
      if (status == ConsultationStatus.expired) _isExpired = true;

      setState(() => _loaded = true);
      _tick();
    });
  }

  // Dipanggil tiap detik: hitung sisa waktu dari deadline di Firestore
  void _tick() {
    if (!mounted || _isSuccess || _deadline == null) return;

    final left = _deadline!.difference(DateTime.now());
    if (left <= Duration.zero) {
      if (!_expireTriggered) {
        _expireTriggered = true;
        expireConsultation(widget.consultationId); // set Expired + lepas slot
      }
      setState(() {
        _isExpired = true;
        _timeLeft = Duration.zero;
      });
    } else {
      setState(() => _timeLeft = left);
    }
  }

  // Simulasi bayar (demo). Hanya berhasil kalau belum kedaluwarsa.
  Future<void> _simulateSuccessfulPayment() async {
    final db = FirebaseFirestore.instance;
    final ref = db.collection('consultations').doc(widget.consultationId);
    try {
      final ok = await db.runTransaction<bool>((tx) async {
        final snap = await tx.get(ref);
        final data = snap.data();
        if (data == null ||
            data['status'] != ConsultationStatus.pending ||
            isPendingExpired(data)) {
          return false;
        }
        tx.update(ref, {
          'status': ConsultationStatus.paid,
          'paidAt': FieldValue.serverTimestamp(),
        });
        return true;
      });
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Waktu pembayaran sudah habis.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal simulasi: $e')),
      );
    }
  }

  // Pop-up Notifikasi Sukses
  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Color(0xFFDCFCE7),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle,
                  size: 60, color: Color(0xFF16A34A)),
            ),
            const SizedBox(height: 16),
            const Text(
              'Pembayaran Berhasil!',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: Color(0xFF1F2937)),
            ),
            const SizedBox(height: 8),
            Text(
              'Transaksi sebesar Rp ${widget.amount.toStringAsFixed(0)} telah terverifikasi.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryDark,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  final nav = Navigator.of(dialogContext);
                  final uid =
                      FirebaseAuth.instance.currentUser?.uid ?? 'user_guest';
                  nav.pop(); // tutup dialog
                  nav.popUntil((route) => route.isFirst); // kembali ke Home
                  nav.push(MaterialPageRoute(
                    builder: (_) => ConsultationHistoryScreen(userId: uid),
                  ));
                },
                child: const Text('Lihat Riwayat Konsultasi',
                    style: TextStyle(color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return '${twoDigits(d.inMinutes)}:${twoDigits(d.inSeconds.remainder(60))}';
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Pembayaran QRIS'),
          backgroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
        ),
        body: const Center(
          child: CircularProgressIndicator(color: primaryDark),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        title: const Text(
          'Pembayaran QRIS',
          style: TextStyle(
              color: Color(0xFF1F2937),
              fontWeight: FontWeight.bold,
              fontSize: 18),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Color(0xFF1F2937)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            // Frame QRIS
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4)),
                ],
              ),
              child: Column(
                children: [
                  // Header Logo QRIS
                  Container(
                    padding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
                    decoration: const BoxDecoration(
                      color: Color(0xFFE11D48), // Merah QRIS
                      borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(20),
                          topRight: Radius.circular(20)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: const [
                        Text('QRIS',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 22,
                                letterSpacing: 1.2)),
                        Text('NMID: ID1020304050',
                            style:
                            TextStyle(color: Colors.white70, fontSize: 11)),
                      ],
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        const Text(
                          'RuangRancang Architecture',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Color(0xFF111827)),
                        ),
                        const SizedBox(height: 4),
                        Text('Order ID: ${widget.consultationId}',
                            style: const TextStyle(
                                fontSize: 12, color: Color(0xFF6B7280))),
                        const SizedBox(height: 12),

                        // Total Harga
                        Text(
                          'Rp ${widget.amount.toStringAsFixed(0)}',
                          style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: primaryDark),
                        ),
                        const SizedBox(height: 12),

                        // Timer Mundur
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: _isExpired
                                ? const Color(0xFFFEE2E2)
                                : const Color(0xFFFEF3C7),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.timer,
                                  size: 16,
                                  color: _isExpired
                                      ? const Color(0xFFB91C1C)
                                      : const Color(0xFFD97706)),
                              const SizedBox(width: 6),
                              Text(
                                _isExpired
                                    ? 'QR Kedaluwarsa'
                                    : 'Bayar dalam ${_formatDuration(_timeLeft)}',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: _isExpired
                                        ? const Color(0xFFB91C1C)
                                        : const Color(0xFFD97706),
                                    fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Gambar QRIS / tampilan kedaluwarsa
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            border:
                            Border.all(color: Colors.grey.shade300, width: 2),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: _isExpired
                              ? const SizedBox(
                            width: 200,
                            height: 200,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.qr_code_2,
                                    size: 80, color: Colors.grey),
                                SizedBox(height: 8),
                                Text('Waktu pembayaran habis',
                                    style: TextStyle(
                                        color: Colors.grey,
                                        fontWeight: FontWeight.w600)),
                              ],
                            ),
                          )
                              : Image.network(
                            _qrImageUrl,
                            width: 200,
                            height: 200,
                            errorBuilder: (_, __, ___) => const SizedBox(
                              width: 200,
                              height: 200,
                              child: Center(
                                child: Text(
                                  'Gagal memuat QR.\nPeriksa koneksi internet.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _isExpired
                              ? 'Jadwal konsultasi dibatalkan dan slot jam dilepas. Silakan buat janji baru.'
                              : 'Bisa discan menggunakan BCA, Mandiri, GoPay, OVO, ShopeePay, Dana, dll.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 11, color: Color(0xFF9CA3AF)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            if (_isExpired)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryDark,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Kembali',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              )
            else
            // Tombol simulasi (demo)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Opsi Simulasi Pembayaran (Demo):',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Color(0xFF374151))),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF16A34A),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: _simulateSuccessfulPayment,
                        icon: const Icon(Icons.qr_code_scanner,
                            color: Colors.white, size: 18),
                        label: const Text('Simulasi Scan & Bayar Berhasil',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}