from PIL import Image

# Image dimensions (adjust if needed)
width, height = 640, 480

# Read RGB565 data from .mem file
with open("captured_output.mem", "r") as f:
    lines = f.readlines()

# Convert hex strings to integers
pixels_rgb565 = [int(line.strip(), 16) for line in lines if line.strip()]

# Convert RGB565 to RGB888
def rgb565_to_rgb888(pixel):
    r = ((pixel >> 11) & 0x1F) << 3
    g = ((pixel >> 5) & 0x3F) << 2
    b = (pixel & 0x1F) << 3
    return (r, g, b)

pixels_rgb888 = [rgb565_to_rgb888(p) for p in pixels_rgb565]

# Create and save image
img = Image.new("RGB", (width, height))
img.putdata(pixels_rgb888)
img.save("output_image.png")

print("✅ Image saved as output_image.png")