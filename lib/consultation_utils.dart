import 'package:cloud_firestore/cloud_firestore.dart';

/// Batas waktu pembayaran QR (menit). Ubah di sini kalau mau lebih lama/singkat.
const int kBatasBayarMenit = 20;

/// ====== GANTI dengan data asli sebelum demo ======
/// Link meeting online (Zoom / Google Meet) yang dipakai semua sesi.
const String kLinkMeeting = 'https://meet.google.com/xxx-xxxx-xxx';

/// Alamat studio untuk konsultasi tatap muka (semua klien di Jakarta).
const String kAlamatStudio =
    'RuangRancang Studio, Jl. Contoh No. 1, Jakarta Selatan';
/// =================================================

/// Lama satu sesi konsultasi (menit).
const int kDurasiSesiMenit = 120;

/// Tombol "Gabung Meeting" aktif sekian menit sebelum jam mulai.
const int kAksesMeetingSebelumMenit = 15;

/// Ubah teks slot seperti "09:00 WIB" + tanggal menjadi waktu mulai sesi.
/// Mengembalikan null kalau format jam tidak terbaca.
DateTime? parseSlotStart(DateTime date, String timeSlot) {
  final m = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(timeSlot);
  if (m == null) return null;
  return DateTime(date.year, date.month, date.day, int.parse(m.group(1)!),
      int.parse(m.group(2)!));
}

/// Nilai status konsultasi, supaya tidak salah ketik di banyak file.
class ConsultationStatus {
  ConsultationStatus._();
  static const pending = 'Pending'; // menunggu pembayaran
  static const paid = 'Paid'; // sudah dibayar
  static const expired = 'Expired'; // waktu bayar habis, slot dilepas
}

/// ID dokumen di koleksi `booked_slots`, contoh: "2026-10-22_09:00".
String slotDocId(String dateString, String timeSlot) =>
    '${dateString}_$timeSlot';

DateTime? deadlineOf(Map<String, dynamic> data) =>
    (data['paymentDeadline'] as Timestamp?)?.toDate();

/// True kalau status masih Pending tapi batas bayar sudah lewat.
bool isPendingExpired(Map<String, dynamic> data) {
  final deadline = deadlineOf(data);
  return data['status'] == ConsultationStatus.pending &&
      deadline != null &&
      DateTime.now().isAfter(deadline);
}

/// Tandai konsultasi sebagai Expired dan lepaskan slot jamnya.
/// Aman dipanggil berkali-kali: kalau sudah dibayar / belum lewat batas, tidak melakukan apa-apa.
Future<void> expireConsultation(String consultationId) async {
  final db = FirebaseFirestore.instance;
  final ref = db.collection('consultations').doc(consultationId);
  try {
    await db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final data = snap.data();
      if (data == null || !isPendingExpired(data)) return;

      final dateString = data['dateString'] as String?;
      final timeSlot = data['timeSlot'] as String?;
      DocumentReference<Map<String, dynamic>>? slotRef;
      bool slotMilikIni = false;
      if (dateString != null && timeSlot != null) {
        slotRef =
            db.collection('booked_slots').doc(slotDocId(dateString, timeSlot));
        final slotSnap = await tx.get(slotRef); // semua read sebelum write
        slotMilikIni =
            slotSnap.exists && slotSnap.data()?['consultationId'] == ref.id;
      }

      tx.update(ref, {
        'status': ConsultationStatus.expired,
        'expiredAt': FieldValue.serverTimestamp(),
      });
      if (slotMilikIni && slotRef != null) tx.delete(slotRef);
    });
  } catch (_) {
    // Gagal (misal offline / rules): tidak fatal, akan dicoba lagi lain waktu.
  }
}