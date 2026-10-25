import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'consultation_utils.dart';
import 'payment_screen.dart';
import 'services/pengaturan_service.dart';

class ConsultationBookingScreen extends StatefulWidget {
  final String userId;

  const ConsultationBookingScreen({Key? key, required this.userId})
      : super(key: key);

  @override
  State<ConsultationBookingScreen> createState() =>
      _ConsultationBookingScreenState();
}

class _ConsultationBookingScreenState extends State<ConsultationBookingScreen> {
  final _formKey = GlobalKey<FormState>();

  /// Tanggal paling awal yang boleh dipilih = besok jam 00:00 (aturan H-1).
  static DateTime _besok() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day + 1);
  }

  DateTime _selectedDate = _besok();
  String? _selectedTimeSlot;
  String _selectedMethod = 'Online';
  String _selectedStyle = 'Minimalis Modern';

  final TextEditingController _landAreaController = TextEditingController();
  final TextEditingController _budgetController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  bool _isLoading = false;

  final List<String> _timeSlots = [
    '09:00 WIB',
    '11:00 WIB',
    '14:00 WIB',
    '16:00 WIB',
    '19:00 WIB',
  ];

  final List<String> _houseStyles = [
    'Minimalis Modern',
    'Klasik',
    'Skandinavia',
    'Industrial',
    'Tropis'
  ];

  @override
  void dispose() {
    _landAreaController.dispose();
    _budgetController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: const Color(0xFFB91C1C)),
    );
  }

  Future<void> _bookConsultation() async {
    if (!_formKey.currentState!.validate() || _selectedTimeSlot == null) {
      _showError('Harap lengkapi formulir dan pilih slot jam.');
      return;
    }

    // Aturan H-1: tidak boleh memesan untuk hari ini (atau yang sudah lewat).
    if (_selectedDate.isBefore(_besok())) {
      _showError('Konsultasi minimal dipesan H-1 (mulai besok).');
      return;
    }

    setState(() => _isLoading = true);

    final db = FirebaseFirestore.instance;
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? widget.userId;
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final timeSlot = _selectedTimeSlot!;

    // Harga diambil dari pengaturan admin (satu sumber, tidak hardcode lagi).
    final pengaturan = await PengaturanService.ambil();
    final harga = pengaturan.hargaKonsultasi.toDouble();

    final slotDocRef =
    db.collection('booked_slots').doc(slotDocId(dateStr, timeSlot));
    final consultationRef = db.collection('consultations').doc();
    final deadline =
    DateTime.now().add(const Duration(minutes: kBatasBayarMenit));

    try {
      await db.runTransaction((transaction) async {
        final slotSnap = await transaction.get(slotDocRef);

        if (slotSnap.exists) {
          // Slot sudah ada isinya. Boleh dipakai ulang HANYA kalau pemesan
          // sebelumnya tidak jadi bayar (kedaluwarsa / dibatalkan).
          final oldId = slotSnap.data()?['consultationId'] as String?;
          if (oldId == null) {
            throw Exception('Slot jam ini sudah dipesan pengguna lain.');
          }
          final oldRef = db.collection('consultations').doc(oldId);
          final oldSnap = await transaction.get(oldRef);
          final old = oldSnap.data();

          final bebas = old == null ||
              old['status'] == ConsultationStatus.expired ||
              old['status'] == 'Cancelled' ||
              isPendingExpired(old);
          if (!bebas) {
            throw Exception('Slot jam ini sudah dipesan pengguna lain.');
          }
          if (old != null && isPendingExpired(old)) {
            transaction
                .update(oldRef, {'status': ConsultationStatus.expired});
          }
        }

        transaction.set(slotDocRef, {
          'bookedAt': FieldValue.serverTimestamp(),
          'userId': currentUid,
          'consultationId': consultationRef.id,
        });

        transaction.set(consultationRef, {
          'userId': currentUid,
          'date': Timestamp.fromDate(_selectedDate),
          'dateString': dateStr,
          'timeSlot': timeSlot,
          'method': _selectedMethod,
          'landArea': double.tryParse(_landAreaController.text) ?? 0,
          'budgetRange': _budgetController.text,
          'houseStyle': _selectedStyle,
          'notes': _notesController.text,
          'price': harga,
          'status': ConsultationStatus.pending,
          'paymentDeadline': Timestamp.fromDate(deadline),
          'createdAt': FieldValue.serverTimestamp(),
        });
      });

      if (!mounted) return;
      setState(() => _isLoading = false);

      // Pindah ke PaymentScreen sambil membawa ID konsultasi
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => PaymentScreen(
            consultationId: consultationRef.id,
            amount: harga,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError(e.toString().replaceAll('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    const primaryDark = Color(0xFF2C3E35);
    final besok = _besok();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Form Konsultasi Desain',
            style: TextStyle(
                color: Colors.black87,
                fontSize: 18,
                fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Info aturan booking
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'Konsultasi dipesan minimal H-1 (mulai besok). '
                      'Setelah submit, selesaikan pembayaran QR dalam '
                      '$kBatasBayarMenit menit, kalau tidak jadwal otomatis dibatalkan.',
                  style: TextStyle(fontSize: 12.5, color: Color(0xFF92400E)),
                ),
              ),
              const SizedBox(height: 20),

              const Text('Metode Konsultasi',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: const Center(child: Text('Online (Zoom/GMeet)')),
                      selected: _selectedMethod == 'Online',
                      selectedColor: primaryDark.withOpacity(0.2),
                      onSelected: (val) =>
                          setState(() => _selectedMethod = 'Online'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ChoiceChip(
                      label: const Center(child: Text('Datang ke Studio')),
                      selected: _selectedMethod == 'Offline',
                      selectedColor: primaryDark.withOpacity(0.2),
                      onSelected: (val) =>
                          setState(() => _selectedMethod = 'Offline'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              const Text('Pilih Tanggal',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _selectedDate,
                    firstDate: besok, // hari ini tidak bisa dipilih
                    lastDate: besok.add(const Duration(days: 60)),
                  );
                  if (picked != null) setState(() => _selectedDate = picked);
                },
                child: Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade400),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(DateFormat('EEEE, dd MMMM yyyy')
                          .format(_selectedDate)),
                      const Icon(Icons.calendar_today,
                          size: 18, color: primaryDark),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              const Text('Pilih Jam Konsultasi',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _timeSlots.map((slot) {
                  final isSelected = _selectedTimeSlot == slot;
                  return ChoiceChip(
                    label: Text(slot),
                    selected: isSelected,
                    selectedColor: primaryDark,
                    labelStyle: TextStyle(
                        color: isSelected ? Colors.white : Colors.black87),
                    onSelected: (val) =>
                        setState(() => _selectedTimeSlot = val ? slot : null),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),

              TextFormField(
                controller: _landAreaController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Luas Lahan / Bangunan (m²)',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                validator: (val) =>
                val == null || val.isEmpty ? 'Harap isi luas lahan' : null,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _budgetController,
                decoration: InputDecoration(
                  labelText: 'Estimasi Budget Pembangunan',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                validator: (val) => val == null || val.isEmpty
                    ? 'Harap isi estimasi budget'
                    : null,
              ),
              const SizedBox(height: 16),

              DropdownButtonFormField<String>(
                value: _selectedStyle,
                decoration: InputDecoration(
                  labelText: 'Gaya Desain Impian',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                items: _houseStyles.map((style) {
                  return DropdownMenuItem(value: style, child: Text(style));
                }).toList(),
                onChanged: (val) => setState(() => _selectedStyle = val!),
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _notesController,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Catatan Tambahan (Kebutuhan Ruangan, dll)',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 30),

              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryDark,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _isLoading ? null : _bookConsultation,
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Lanjut Pembayaran',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}