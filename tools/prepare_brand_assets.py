from PIL import Image

src = Image.open('png.png').convert('RGBA')
pixels = src.load()
w, h = src.size
for y in range(h):
    for x in range(w):
        r, g, b, a = pixels[x, y]
        if r < 28 and g < 28 and b < 28:
            pixels[x, y] = (0, 0, 0, 0)

bbox = src.getbbox()
logo = src.crop(bbox) if bbox else src
logo.save('assets/brand/logo_transparent.png')

side = max(logo.size)
pad = int(side * 0.18)
canvas_size = side + pad * 2
fg = Image.new('RGBA', (canvas_size, canvas_size), (0, 0, 0, 0))
ox = (canvas_size - logo.size[0]) // 2
oy = (canvas_size - logo.size[1]) // 2
fg.paste(logo, (ox, oy), logo)
fg = fg.resize((1024, 1024), Image.Resampling.LANCZOS)
fg.save('assets/brand/ic_launcher_foreground.png')

bg = Image.new('RGBA', (1024, 1024), (31, 77, 58, 255))  # #1F4D3A
inset = int(1024 * 0.12)
scaled = logo.copy()
scaled.thumbnail((1024 - inset * 2, 1024 - inset * 2), Image.Resampling.LANCZOS)
ox = (1024 - scaled.size[0]) // 2
oy = (1024 - scaled.size[1]) // 2
bg.paste(scaled, (ox, oy), scaled)
bg.save('assets/brand/ic_launcher.png')
print('logo', logo.size, 'fg', fg.size, 'icon', bg.size)
