import struct, os, sys

def create_vtf(path, w, h):
    """Create a minimal valid VTF 7.2 file with proper magic bytes."""
    # VTF 7.2 header is 64 bytes (or 80 for 7.3+)
    header = bytearray(64)
    # Magic: "VTF\0" (0x56 0x54 0x46 0x00)
    header[0:4] = b'VTF\x00'
    # Version: major=7, minor=2
    struct.pack_into('<I', header, 4, 7)   # versionMajor
    struct.pack_into('<I', header, 8, 2)  # versionMinor
    struct.pack_into('<I', header, 12, 64) # headerSize (64 for v7.2)
    # Width, Height
    struct.pack_into('<H', header, 16, w)
    struct.pack_into('<H', header, 18, h)
    # Flags: 0x4000 = SRGB
    struct.pack_into('<I', header, 20, 0x4000)
    # numFrames
    struct.pack_into('<H', header, 24, 1)
    # numMipLevels
    header[28] = 1
    # imageFormat: RGBA8888 = 12 (offset 36 in v7.2)
    struct.pack_into('<I', header, 36, 12)
    # lowResImageFormat: RGBA8888
    struct.pack_into('<I', header, 40, 12)
    header[44] = 1  # lowResImageWidth
    header[45] = 1  # lowResImageHeight
    
    # Image data: 1x1 low-res RGBA + full-res RGBA
    low_res = bytes([128, 128, 128, 255])
    full_res = bytes([128, 128, 128, 255] * (w * h))
    
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'wb') as f:
        f.write(header)
        f.write(low_res)
        f.write(full_res)

base = sys.argv[1] if len(sys.argv) > 1 else '.'
for path, w, h in [
    (base+'/dev/identitylightwarp.vtf', 64, 1),
    (base+'/engine/normalizedrandomdirections2d.vtf', 256, 256),
    (base+'/effects/flashlight_border.vtf', 128, 128),
]:
    if not os.path.exists(path):
        create_vtf(path, w, h)
        print(f'  Created dummy VTF: {path}')
    else:
        # Check if existing file has correct magic
        with open(path, 'rb') as f:
            magic = f.read(4)
        if magic != b'VTF\x00':
            create_vtf(path, w, h)
            print(f'  Fixed VTF (was corrupt): {path}')
