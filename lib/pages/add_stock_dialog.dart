import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core.dart';

class AddStockDialog extends StatefulWidget {
  final Product p;
  const AddStockDialog({super.key, required this.p});
  @override
  State<AddStockDialog> createState() => _AddStockDialogState();
}

class _AddStockDialogState extends State<AddStockDialog> {
  final c = TextEditingController();

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  int get n => int.tryParse(c.text) ?? 0;

  @override
  Widget build(BuildContext context) {
    final cur = widget.p.stock ?? 0;
    return AlertDialog(
      title: const Text('Tambah stok'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('Stok saat ini: ${nf(cur)} pcs', style: const TextStyle(color: muted)),
        const SizedBox(height: 14),
        TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(labelText: 'Jumlah yang ditambah', suffixText: 'pcs', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => n > 0 ? Navigator.pop(context, n) : null,
        ),
        const SizedBox(height: 12),
        Text('Stok menjadi: ${nf(cur + n)} pcs', style: const TextStyle(fontWeight: FontWeight.w800, color: brand)),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: brand),
          onPressed: n > 0 ? () => Navigator.pop(context, n) : null,
          child: const Text('Tambah'),
        ),
      ],
    );
  }
}