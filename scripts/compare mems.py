def compare_mem_files(file1, file2):
    with open(file1, 'r') as f1, open(file2, 'r') as f2:
        lines1 = [line.strip().lower() for line in f1.readlines()]
        lines2 = [line.strip().lower() for line in f2.readlines()]

    if lines1 == lines2:
        print("✅ The files are identical.")
    else:
        print("❌ The files are different.")
        # Optional: show first mismatch
        for i, (a, b) in enumerate(zip(lines1, lines2)):
            if a != b:
                print(f"Mismatch at line {i}: {a} != {b}")
                break

# Replace with your actual file paths
compare_mem_files('image.mem', 'captured_output.mem')
