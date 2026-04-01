from PIL import Image
import os, hashlib

assets = r'C:\Users\silvi\Documents\Projekte\whispaste\msix\Assets'
for f in sorted(os.listdir(assets)):
    if not f.endswith('.png') or 'targetsize' not in f:
        continue
    path = os.path.join(assets, f)
    img = Image.open(path)
    w, h = img.size
    md5 = hashlib.md5(open(path,'rb').read()).hexdigest()[:8]
    corners = []
    if img.mode == 'RGBA':
        for x, y in [(0,0), (w-1,0), (0,h-1), (w-1,h-1)]:
            corners.append(img.getpixel((x, y)))
    print(f'{f}: {w}x{h} {img.mode} md5={md5} corners={corners}')
