with open('lib/main.dart') as f:
    content = f.read()
old = "                            }),\n                          ),\n                            TextButton(child: Text('Select'), onPressed: () { Navigator.pop(ctx); _toggleBatchSelection(path); }),"
new = "                            }),\n                          ),\n                        ),\n                            TextButton(child: Text('Select'), onPressed: () { Navigator.pop(ctx); _toggleBatchSelection(path); }),"
content = content.replace(old, new)
with open('lib/main.dart', 'w') as f:
    f.write(content)
print('done')
