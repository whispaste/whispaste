import re
with open('ui_main/pages/02-settings.html', 'r', encoding='utf-8') as f:
    lines = f.readlines()
depth = 0
for i, line in enumerate(lines, 1):
    opens = len(re.findall(r'<div[\s>]', line))
    closes = len(re.findall(r'</div>', line))
    depth += opens - closes
    if (opens or closes) and 100 < i < 250:
        print(f'L{i:4d} d={depth:3d} +{opens}/-{closes}: {line.rstrip()[:90]}')
print(f'Final depth: {depth}')
