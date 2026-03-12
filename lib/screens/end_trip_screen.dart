import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:trackersales/providers/auth_provider.dart';
import 'package:trackersales/providers/trip_provider.dart';
import 'package:trackersales/theme/app_theme.dart';
import 'package:google_fonts/google_fonts.dart';

class EndTripScreen extends StatefulWidget {
  final double distanceKm;
  final String durationStr;

  const EndTripScreen({
    super.key,
    required this.distanceKm,
    required this.durationStr,
  });

  @override
  State<EndTripScreen> createState() => _EndTripScreenState();
}

class _EndTripScreenState extends State<EndTripScreen> {
  final _formKey = GlobalKey<FormState>();
  final _notesController = TextEditingController();
  
  List<dynamic> _expenseTypes = [];
  final List<Map<String, dynamic>> _addedExpenses = [];
  
  String? _selectedExpenseTypeId;
  final _expenseAmountController = TextEditingController();
  bool _isLoadingExpenses = true;

  @override
  void initState() {
    super.initState();
    _fetchExpenseTypes();
  }

  Future<void> _fetchExpenseTypes() async {
    final user = Provider.of<AuthProvider>(context, listen: false).user;
    if (user != null) {
      final tripProvider = Provider.of<TripProvider>(context, listen: false);
      final result = await tripProvider.fetchExpenseTypes(user.systemUserId);
      if (result['success']) {
        if (mounted) {
          setState(() {
            _expenseTypes = result['data'];
            _isLoadingExpenses = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _isLoadingExpenses = false;
          });
        }
      }
    }
  }

  void _addExpense() {
    if (_selectedExpenseTypeId != null && _expenseAmountController.text.isNotEmpty) {
      final type = _expenseTypes.firstWhere((e) => e['expense_type_id'].toString() == _selectedExpenseTypeId);
      
      setState(() {
        _addedExpenses.add({
          "expense_type_id": _selectedExpenseTypeId,
          "expense_name": type['name'],
          "amount": _expenseAmountController.text.trim()
        });
        _selectedExpenseTypeId = null;
        _expenseAmountController.clear();
      });
    }
  }

  void _removeExpense(int index) {
    setState(() {
      _addedExpenses.removeAt(index);
    });
  }

  @override
  void dispose() {
    _notesController.dispose();
    _expenseAmountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text("Complete Trip", style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context, null),
        ),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Stats Header
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: Colors.grey[100]!),
                        ),
                        child: Row(
                          children: [
                            _statItem("Distance", "${widget.distanceKm.toStringAsFixed(2)} km", Icons.route_rounded, Colors.blue),
                            Container(width: 1, height: 40, color: Colors.grey[200], margin: const EdgeInsets.symmetric(horizontal: 20)),
                            _statItem("Duration", widget.durationStr, Icons.timer_rounded, Colors.orange),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 32),
                      Text("PURPOSE OF VISIT / NOTES *", style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey[500], letterSpacing: 1)),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _notesController,
                        maxLines: 3,
                        decoration: InputDecoration(
                          hintText: "Enter trip details (Mandatory)",
                          filled: true,
                          fillColor: Colors.grey[50],
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                          contentPadding: const EdgeInsets.all(16),
                        ),
                        validator: (value) => value == null || value.trim().isEmpty ? "Notes are required" : null,
                      ),

                      const SizedBox(height: 32),
                      Text("EXPENSES (OPTIONAL)", style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey[500], letterSpacing: 1)),
                      const SizedBox(height: 12),
                      
                      if (_isLoadingExpenses)
                        const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
                      else ...[
                        _buildExpenseInputs(),
                        const SizedBox(height: 16),
                        _buildExpenseList(),
                      ],
                    ],
                  ),
                ),
              ),
              
              // Bottom Action Button
              Padding(
                padding: const EdgeInsets.all(24),
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    child: Text("Finish Trip", style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statItem(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(label, style: GoogleFonts.outfit(fontSize: 12, color: Colors.grey[500])),
            ],
          ),
          const SizedBox(height: 4),
          Text(value, style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildExpenseInputs() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        children: [
          DropdownButtonFormField<String>(
            isExpanded: true,
            value: _selectedExpenseTypeId,
            hint: const Text("Select Expense Type"),
            decoration: const InputDecoration(border: InputBorder.none, contentPadding: EdgeInsets.zero),
            items: _expenseTypes.map((e) {
              return DropdownMenuItem<String>(
                value: e['expense_type_id'].toString(),
                child: Text(e['name'].toString()),
              );
            }).toList(),
            onChanged: (val) => setState(() => _selectedExpenseTypeId = val),
          ),
          const Divider(),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _expenseAmountController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(hintText: "Enter Amount", border: InputBorder.none, prefixText: "₹ "),
                ),
              ),
              IconButton(
                onPressed: _addExpense,
                icon: const Icon(Icons.add_circle_rounded, color: Colors.black, size: 32),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildExpenseList() {
    if (_addedExpenses.isEmpty) return const SizedBox.shrink();

    return Column(
      children: _addedExpenses.asMap().entries.map((entry) {
        int i = entry.key;
        var exp = entry.value;
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.green[50],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.green[100]!),
          ),
          child: Row(
            children: [
              Expanded(child: Text(exp['expense_name'], style: GoogleFonts.outfit(fontWeight: FontWeight.w600))),
              Text("₹${exp['amount']}", style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.green[700])),
              const SizedBox(width: 8),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => _removeExpense(i),
                icon: const Icon(Icons.remove_circle_outline_rounded, color: Colors.red, size: 20),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      if (_selectedExpenseTypeId != null && _expenseAmountController.text.isNotEmpty) {
        _addExpense();
      }

      final List<Map<String, dynamic>> formattedExpenses = _addedExpenses.map<Map<String, dynamic>>((e) => {
        "expense_type_id": e["expense_type_id"].toString(),
        "amount": e["amount"].toString()
      }).toList();
      
      Navigator.pop(context, {
        'notes': _notesController.text.trim(),
        'expenses': formattedExpenses
      });
    }
  }
}
