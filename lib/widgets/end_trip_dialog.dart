import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:trackersales/providers/auth_provider.dart';
import 'package:trackersales/providers/trip_provider.dart';
import 'package:trackersales/theme/app_theme.dart';

class EndTripDialog extends StatefulWidget {
  final double distanceKm;
  final String durationStr;

  const EndTripDialog({
    super.key,
    required this.distanceKm,
    required this.durationStr,
  });

  @override
  State<EndTripDialog> createState() => _EndTripDialogState();
}

class _EndTripDialogState extends State<EndTripDialog> {
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
      // Find the name for UI
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

  Widget _dialogStatItem(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: Colors.blue[600]),
              const SizedBox(width: 8),
              Text(label),
            ],
          ),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _notesController.dispose();
    _expenseAmountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Icon(Icons.check_circle_outline, color: Colors.green[600]),
          const SizedBox(width: 10),
          const Text("Complete Trip"),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      _dialogStatItem("Distance", "${widget.distanceKm.toStringAsFixed(2)} km", Icons.straighten),
                      const Divider(),
                      _dialogStatItem("Duration", widget.durationStr, Icons.timer_outlined),
                    ],
                  ),
                ),
                // Notes and expenses UI commented out because backend EndTrip
                // API does not require these parameters. Left here for easy
                // restoration if the requirements change in future.
                //
                // const SizedBox(height: 20),
                // const Text("Purpose of Visit / Notes *", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                // const SizedBox(height: 8),
                // TextFormField(
                //   controller: _notesController,
                //   maxLines: 2,
                //   decoration: InputDecoration(
                //     hintText: "Enter details (Compulsory)...",
                //     filled: true,
                //     fillColor: Colors.grey[100],
                //     border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                //     contentPadding: const EdgeInsets.all(12),
                //   ),
                //   validator: (value) => value == null || value.trim().isEmpty ? "Notes are mandatory" : null,
                // ),
                //
                // const SizedBox(height: 20),
                // const Text("Expenses (Optional)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                // const SizedBox(height: 8),
                //
                // if (_isLoadingExpenses)
                //    const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator(strokeWidth: 2)))
                // else if (_expenseTypes.isNotEmpty) ...[
                //   Row(
                //     children: [
                //       Expanded(
                //         flex: 3,
                //         child: DropdownButtonFormField<String>(
                //           isExpanded: true,
                //           value: _selectedExpenseTypeId,
                //           hint: const Text("Select Expense", style: TextStyle(fontSize: 12)),
                //           decoration: InputDecoration(
                //             isDense: true,
                //             contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                //             filled: true,
                //             fillColor: Colors.grey[100],
                //             border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                //           ),
                //           items: _expenseTypes.map((e) {
                //             return DropdownMenuItem<String>(
                //               value: e['expense_type_id'].toString(),
                //               child: Text(e['name'].toString(), style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
                //             );
                //           }).toList(),
                //           onChanged: (val) {
                //             setState(() {
                //               _selectedExpenseTypeId = val;
                //             });
                //           },
                //         ),
                //       ),
                //       const SizedBox(width: 8),
                //       Expanded(
                //         flex: 2,
                //         child: TextFormField(
                //           controller: _expenseAmountController,
                //           keyboardType: TextInputType.number,
                //           decoration: InputDecoration(
                //             isDense: true,
                //             hintText: "Amount",
                //             hintStyle: const TextStyle(fontSize: 12),
                //             filled: true,
                //             fillColor: Colors.grey[100],
                //             contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                //             border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                //           ),
                //         ),
                //       ),
                //       IconButton(
                //         icon: const Icon(Icons.add_circle, color: AppTheme.primaryColor),
                //         onPressed: _addExpense,
                //       )
                //     ],
                //   ),
                // ],
                //
                // if (_addedExpenses.isNotEmpty) ...[
                //   const SizedBox(height: 12),
                //   ListView.builder(
                //     shrinkWrap: true,
                //     physics: const NeverScrollableScrollPhysics(),
                //     itemCount: _addedExpenses.length,
                //     itemBuilder: (ctx, i) {
                //       final exp = _addedExpenses[i];
                //       return Container(
                //         margin: const EdgeInsets.only(bottom: 6),
                //         padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                //         decoration: BoxDecoration(
                //           color: Colors.green[50],
                //           border: Border.all(color: Colors.green[200]!),
                //           borderRadius: BorderRadius.circular(8)
                //         ),
                //         child: Row(
                //           children: [
                //             Expanded(child: Text(exp['expense_name'], style: const TextStyle(fontSize: 12))),
                //             Text("₹${exp['amount']}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                //             const SizedBox(width: 8),
                //             GestureDetector(
                //               onTap: () => _removeExpense(i),
                //               child: const Icon(Icons.close, size: 16, color: Colors.red),
                //             )
                //           ],
                //         ),
                //       );
                //     },
                //   )
                // ]
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: Text("Cancel", style: TextStyle(color: Colors.grey[600])),
        ),
        ElevatedButton(
          onPressed: () {
            // Notes and expenses are no longer collected for end trip;
            // always return an empty payload here to preserve the shape.
            Navigator.pop(context, {
              'notes': '',
              'expenses': <Map<String, dynamic>>[],
            });
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
          child: const Text("Submit", style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}
