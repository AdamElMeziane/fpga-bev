def rgb565_to_rgb3(hexval):
    val = int(hexval, 16)
    r = (val >> 11) & 0x1F
    g = (val >> 5) & 0x3F
    b = val & 0x1F
    return ((r >> 4) << 2) | ((g >> 5) << 1) | (b >> 4)

with open("image.txt", "r") as infile, open("image_3bit.mem", "w") as outfile:
    for line in infile:
        hexval = line.strip()
        if hexval:
            rgb3 = rgb565_to_rgb3(hexval)
            outfile.write(f"{rgb3:01x}\n")
