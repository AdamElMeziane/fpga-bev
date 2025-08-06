from PIL import Image

# === Configuration ===
input_image_path = "ayaka_input.png"       # Path to your PNG image
output_mem_path = "image.mem"    # Output .mem file
target_width, target_height = 640, 480     # Target resolution

# === Load and resize image ===
img = Image.open(input_image_path).convert("RGB")
img = img.resize((target_width, target_height))

# === RGB888 to RGB565 conversion ===
def rgb888_to_rgb565(r, g, b):
    return ((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3)

# === Convert pixels ===
pixels = list(img.getdata())
pixels_rgb565 = [rgb888_to_rgb565(r, g, b) for r, g, b in pixels]

# === Write to .mem file ===
with open(output_mem_path, "w") as f:
    for pixel in pixels_rgb565:
        f.write(f"{pixel:04X}\n")

print(f"✅ RGB565 data saved to {output_mem_path}")