from PIL import Image

# === CONFIGURATION ===
input_image_path = "../assets/colors.jpg"  # Replace with your image file
output_mem_path = "../assets/image_3bit.mem"
target_width = 320
target_height = 240

# === PROCESSING ===
def rgb_to_3bit(r, g, b):
    r_bit = 1 if r > 127 else 0
    g_bit = 1 if g > 127 else 0
    b_bit = 1 if b > 127 else 0
    return (r_bit << 2) | (g_bit << 1) | b_bit

img = Image.open(input_image_path).convert("RGB")
img_resized = img.resize((target_width, target_height))
pixels = list(img_resized.getdata())

with open(output_mem_path, "w") as f:
    for pixel in pixels:
        value = rgb_to_3bit(*pixel)
        f.write(f"{value:03b}\n")

print(f"Generated {output_mem_path} with {len(pixels)} entries.")
