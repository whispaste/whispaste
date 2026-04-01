from PIL import Image
import os, hashlib

assets = r'C:\Users\silvi\Documents\Projekte\whispaste\msix\Assets'
for f in sorted(os.listdir(assets)):
    if not f.endswith('.png'):
        continue
    path = os.path.join(assets, f)
    img = Image.open(path)
    w, h = img.size
    md5 = hashlib.md5(open(path,'rb').read()).hexdigest()[:8]
    # Check if has alpha and if corners are transparent
    has_alpha = img.mode == 'RGBA'
    corner_alpha = 'N/A'
    if has_alpha:
        a_vals = [img.getpixel((x,y))[3] for x,y in [(0,0),(w-1,0),(0,h-1),(w-1,h-1)]]
        corner_alpha = f'alpha={a_vals}'
    print(f'{f}: {w}x{h} {img.mode} md5={md5} {corner_alpha}')
