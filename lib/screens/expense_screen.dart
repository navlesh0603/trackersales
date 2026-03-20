import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:trackersales/providers/auth_provider.dart';
import 'package:trackersales/services/expense_service.dart';

// Expense types — update IDs if backend adds more types
const List<Map<String, dynamic>> kExpenseTypes = [
  {'id': 1, 'label': 'Hotel Room Cost'},
  {'id': 2, 'label': 'Food & Meals'},
  {'id': 3, 'label': 'Fuel / Transport'},
  {'id': 4, 'label': 'Parking'},
  {'id': 5, 'label': 'Miscellaneous'},
];

class ExpenseScreen extends StatefulWidget {
  const ExpenseScreen({super.key});

  @override
  State<ExpenseScreen> createState() => _ExpenseScreenState();
}

class _ExpenseScreenState extends State<ExpenseScreen> {
  final ExpenseService _service = ExpenseService();

  bool _loading = true;
  List<dynamic> _expenses = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchExpenses());
  }

  Future<void> _fetchExpenses() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final ap = Provider.of<AuthProvider>(context, listen: false);
    if (ap.user == null) {
      setState(() => _loading = false);
      return;
    }
    final result = await _service.getExpenses(ap.user!.systemUserId);
    if (!mounted) return;
    if (result['success'] == true) {
      setState(() {
        _expenses = (result['expenses'] as List?) ?? [];
        _loading = false;
      });
    } else {
      setState(() {
        _error = result['message'];
        _loading = false;
      });
    }
  }

  void _openAddExpense() {
    final ap = Provider.of<AuthProvider>(context, listen: false);
    if (ap.user == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddExpenseSheet(
        systemUserId: ap.user!.systemUserId,
        onSuccess: () {
          Navigator.pop(context);
          _fetchExpenses();
        },
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          'Expenses',
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w700,
            fontSize: 22,
          ),
        ),
        actions: [
          IconButton(
            onPressed: _fetchExpenses,
            icon: const Icon(Icons.refresh_rounded, color: Colors.black),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.black))
          : _error != null
          ? _buildError()
          : _expenses.isEmpty
          ? _buildEmpty()
          : RefreshIndicator(
              onRefresh: _fetchExpenses,
              color: Colors.black,
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                itemCount: _expenses.length,
                itemBuilder: (context, index) =>
                    _buildExpenseCard(_expenses[index]),
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'expense_add_fab',
        onPressed: _openAddExpense,
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Expense'),
        elevation: 4,
      ),
    );
  }

  Widget _buildExpenseCard(dynamic expense) {
    final type = (expense['expense_type'] ?? 'Expense').toString();
    final amount = expense['amount'];
    final status = (expense['status'] ?? 'Submitted').toString();
    final date = (expense['expense_date'] ?? '').toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[100]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.receipt_long_rounded,
              color: Colors.black,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  type,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  date,
                  style: TextStyle(color: Colors.grey[500], fontSize: 12),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '₹${amount ?? 0}',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _statusColor(status).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    color: _statusColor(status),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return RefreshIndicator(
      onRefresh: _fetchExpenses,
      color: Colors.black,
      child: ListView(
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.5,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.receipt_long_outlined,
                    size: 40,
                    color: Colors.grey[300],
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'No expenses yet',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Tap the button below to add your first expense.',
                  style: TextStyle(color: Colors.grey[400], fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off_rounded, size: 48, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              _error ?? 'Something went wrong.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[500]),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _fetchExpenses,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Add Expense Bottom Sheet
// ---------------------------------------------------------------------------

class _AddExpenseSheet extends StatefulWidget {
  final int systemUserId;
  final VoidCallback onSuccess;

  const _AddExpenseSheet({required this.systemUserId, required this.onSuccess});

  @override
  State<_AddExpenseSheet> createState() => _AddExpenseSheetState();
}

class _AddExpenseSheetState extends State<_AddExpenseSheet> {
  final ExpenseService _service = ExpenseService();
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _amountController = TextEditingController();

  DateTime _selectedDate = DateTime.now();
  int _selectedTypeId = kExpenseTypes[0]['id'] as int;
  String? _photoPath;
  bool _loading = false;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: ThemeData.light().copyWith(
          colorScheme: const ColorScheme.light(primary: Colors.black),
          dialogBackgroundColor: Colors.white,
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _capturePhoto() async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 70,
      );
      if (photo != null && mounted) {
        setState(() => _photoPath = photo.path);
      }
    } on PlatformException catch (e) {
      if (!mounted) return;
      String message;
      if (e.code == 'camera_access_denied' ||
          e.code == 'camera_access_denied_without_prompt') {
        message =
            'Camera permission was denied. You can enable it in app settings to attach receipts.';
      } else {
        message = 'Unable to open camera. Please try again.';
      }
      _snack(message);
    } catch (_) {
      if (!mounted) return;
      _snack('Something went wrong while opening the camera.');
    }
  }

  Future<void> _submit() async {
    final amountText = _amountController.text.trim();
    if (amountText.isEmpty) {
      _snack('Please enter an amount.');
      return;
    }
    final amount = double.tryParse(amountText);
    if (amount == null || amount <= 0) {
      _snack('Please enter a valid amount.');
      return;
    }
    if (_photoPath == null) {
      _snack('Please capture a photo of the receipt.');
      return;
    }

    setState(() => _loading = true);

    final dateStr = DateFormat('dd/MM/yyyy').format(_selectedDate);
    final result = await _service.addExpense(
      systemUserId: widget.systemUserId,
      date: dateStr,
      expenseTypeId: _selectedTypeId,
      amount: amount,
      photoPath: _photoPath!,
    );

    if (!mounted) return;
    setState(() => _loading = false);

    if (result['success'] == true) {
      widget.onSuccess();
    } else {
      _snack(result['message'] ?? 'Failed to add expense.');
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(24, 20, 24, 24 + bottomPad),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Title
          const Text(
            'Add Expense',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 20),

          // Date row
          GestureDetector(
            onTap: _pickDate,
            child: _InputRow(
              icon: Icons.calendar_today_rounded,
              label: 'Date',
              value: DateFormat('dd MMM yyyy').format(_selectedDate),
              trailing: const Icon(
                Icons.chevron_right_rounded,
                color: Colors.grey,
                size: 18,
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Expense type dropdown
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.category_outlined,
                  size: 18,
                  color: Colors.black54,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      value: _selectedTypeId,
                      isExpanded: true,
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedTypeId = val);
                      },
                      items: kExpenseTypes
                          .map(
                            (t) => DropdownMenuItem<int>(
                              value: t['id'] as int,
                              child: Text(t['label'] as String),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Amount field
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.currency_rupee_rounded,
                  size: 18,
                  color: Colors.black54,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _amountController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'^\d+\.?\d{0,2}'),
                      ),
                    ],
                    decoration: const InputDecoration(
                      hintText: 'Amount',
                      border: InputBorder.none,
                      hintStyle: TextStyle(color: Colors.grey, fontSize: 14),
                      contentPadding: EdgeInsets.symmetric(vertical: 12),
                    ),
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Photo capture
          GestureDetector(
            onTap: _capturePhoto,
            child: Container(
              width: double.infinity,
              height: 100,
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _photoPath != null ? Colors.black : Colors.grey[200]!,
                  width: _photoPath != null ? 1.5 : 1,
                ),
              ),
              child: _photoPath != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(11),
                      child: Image.file(
                        File(_photoPath!),
                        fit: BoxFit.cover,
                        width: double.infinity,
                      ),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.add_a_photo_outlined,
                          color: Colors.grey[400],
                          size: 28,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Capture receipt photo (required)',
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 24),

          // Submit button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _loading ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      'Submit Expense',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reusable row widget for sheet items
// ---------------------------------------------------------------------------

class _InputRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Widget? trailing;

  const _InputRow({
    required this.icon,
    required this.label,
    required this.value,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.black54),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 4), trailing!],
        ],
      ),
    );
  }
}
