import struct, os, sys

def create_vtf(path, w, h):
    header = b'\x00\x05\x00\x02'  # VTF v7.2
    header += struct.pack('<I', 64)
    header += struct.pack('<I', 0)
    header += struct.pack('<I', 0)
    header += struct.pack('<H', w)
    header += struct.pack('<H', h)
    header += b'\x00' * 44
    header = header[:64].ljust(64, b'\x00')
    bw, bh = max(w,4), max(h,4)
    bx, by = (bw+3)//4, (bh+3)//4
    block = struct.pack('<HH', 0x7BEF, 0x7BEF) + b'\x00'*8
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'wb') as f:
        f.write(header)
        for _ in range(bx*by): f.write(block)

base = sys.argv[1] if len(sys.argv) > 1 else '.'
for path, w, h in [
    (base+'/dev/identitylightwarp.vtf', 64, 1),
    (base+'/engine/normalizedrandomdirections2d.vtf', 256, 256),
    (base+'/effects/flashlight_border.vtf', 128, 128),
]:
    if not os.path.exists(path):
        create_vtf(path, w, h)
        print(f'  Created dummy VTF: {path}')
