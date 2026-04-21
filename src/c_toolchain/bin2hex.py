import sys

if len(sys.argv) != 3:
    print("Usage: python bin2hex.py <input.bin> <output.hex>")
    sys.exit(1)

input_file = sys.argv[1]
output_file = sys.argv[2]

try:
    with open(input_file, "rb") as f, open(output_file, "w") as out:
        while True:
            chunk = f.read(4)
            if not chunk:
                break
            
            # If the final chunk is less than 4 bytes, pad it with NOPs (zeros)
            if len(chunk) < 4:
                chunk = chunk + b'\x00' * (4 - len(chunk))
            
            # Reverse the bytes for Little Endian architecture correctly aligning for the pipeline bus
            reversed_chunk = chunk[::-1]
            out.write(reversed_chunk.hex() + '\n')
            
    print(f"Successfully converted {input_file} -> {output_file}")
except Exception as e:
    print(f"Error during conversion: {e}")
    sys.exit(1)
