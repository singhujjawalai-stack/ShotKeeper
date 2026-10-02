with open('lib/main.dart') as f:
    lines = f.read().splitlines()

# Find the line containing "                            TextButton(child: Text('Select'), onPressed"
for i, line in enumerate(lines):
    if "TextButton(child: Text('Select'), onPressed: () { Navigator.pop(ctx); _toggleBatchSelection(path); })," in line:
        print(f"Found at line {i+1}: {line}")
        # We need to fix from line 476 (the extra ) at line 476) and the missing inner close
        # The section from lines 413-500 needs restructuring.
        # Let's just replace the broken segment from line 413 onward with corrected version.

# Actually easiest: rebuild from line 411 to end of file with correct syntax
start_idx = 410  # 0-based, line 411
end_idx = len(lines)

new_segment = '''                      return InkWell(
                        onTap: () {
                          showDialog(context: context, builder: (ctx) => AlertDialog(
                            title: Text('Options'),
                            content: Text('Choose action'),
                            actions: [
                              TextButton(child: Text('View'), onPressed: () { Navigator.pop(ctx); showDialog(context: context, builder: (c) => AlertDialog(title: Text('View'), content: path.isNotEmpty ? Image.file(File(path), fit: BoxFit.cover) : Text('No image'), actions: [TextButton(child: Text('Close'), onPressed: () => Navigator.pop(c))]))); }),
                              TextButton(child: Text('Schedule Delete'), onPressed: () {
                                Navigator.pop(ctx);
                                RetentionPeriod tempPeriod = _selectedPeriod;
                                showDialog(context: context, builder: (c) => StatefulBuilder(
                                  builder: (ctx2, setStateLocal) {
                                    final valueController = TextEditingController(text: '4');
                                    String unitValue = 'hours';
                                    return AlertDialog(
                                      title: Text('Schedule Deletion'),
                                      content: StatefulBuilder(
                                        builder: (innerCtx, innerSet) {
                                          return Column(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              const Text('Select retention period:'),
                                              const SizedBox(height: 8),
                                              Row(
                                                children: [
                                                  Expanded(
                                                    flex: 1,
                                                    child: TextField(
                                                      controller: valueController,
                                                      keyboardType: TextInputType.number,
                                                      decoration: const InputDecoration(labelText: 'Value', border: OutlineInputBorder()),
                                                      onChanged: (v) { innerSet(() {}); },
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    flex: 2,
                                                    child: DropdownButtonFormField<String>(
                                                      value: unitValue,
                                                      decoration: const InputDecoration(labelText: 'Unit', border: OutlineInputBorder()),
                                                      items: ['minutes','hours','days','weeks','months','years'].map((unit) => DropdownMenuItem(value: unit, child: Text(unit))).toList(),
                                                      onChanged: (v) { if (v != null) { unitValue = v; innerSet(() {}); } },
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 8),
                                              Text('Will delete by: ${_computeDeleteDateLive(valueController.text, unitValue)}'),
                                            ],
                                          );
                                        },
                                      ),
                                    actions: [
                                      TextButton(child: Text('Cancel'), onPressed: () => Navigator.pop(c)),
                                      TextButton(child: Text('Confirm'), onPressed: () {
                                        Navigator.pop(c);
                                        Navigator.pop(context);
                                        _openScheduleScreen(path);
                                      }),
                                    ],
                                  ),
                                );
                              }),
                            }),
                            TextButton(child: Text('Select'), onPressed: () { Navigator.pop(ctx); _toggleBatchSelection(path); }),
                            ],
                          ),
                        ),
                        child: Stack(
                          children: [
                            Card(
                              child: path.isNotEmpty ? Image.file(File(path), fit: BoxFit.cover) : Container(color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1A1A2E) : const Color(0xFFEAEAEA), child: Center(child: Text(name, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.secondary)))),
                            ),
                            if (_selectedBatchPaths.contains(path))
                              Positioned(
                                top: 4, right: 4,
                                child: Container(
                                  decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, shape: BoxShape.circle),
                                  padding: const EdgeInsets.all(4),
                                  child: const Icon(Icons.check, color: Colors.white, size: 14),
                                ),
                              ),
                          ],
                        ),
                      );
                    }).toList()),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}'''

with open('lib/main.dart', 'w') as f:
    f.write('\n'.join(lines[:start_idx]) + '\n' + new_segment)
print('rewritten')
