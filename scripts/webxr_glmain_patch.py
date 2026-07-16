#!/usr/bin/env python3
"""
Patch gl_rmain.cpp to add WebXR camera matrix override.

Adds:
1. extern declarations for g_WebXRViewMatrix and g_bWebXRMatrixActive (after includes)
2. Matrix override check in ComputeViewMatrix() — if g_bWebXRMatrixActive is true,
   copies the WebXR 4x4 view matrix directly instead of computing from angles.

Usage: python3 webxr_glmain_patch.py <path_to_gl_rmain.cpp>
"""
import sys
import re

def patch_file(filepath):
    with open(filepath, 'r') as f:
        content = f.read()

    # 1. Add extern declarations after the last #include
    extern_block = '''
// --- WebXR camera matrix override (defined in webxr_hooks.cpp) ---
#ifdef __EMSCRIPTEN__
extern float g_WebXRViewMatrix[];
extern bool g_bWebXRMatrixActive;
#endif
'''

    if 'g_WebXRViewMatrix' in content:
        print(f"  webxr_glmain: already patched, skipping")
        return

    # Find the last #include line and insert after it
    # Look for the last occurrence of #include in the header block
    include_pattern = r'(#include "[^"]+"\n)(?=\n)'
    matches = list(re.finditer(include_pattern, content))
    if matches:
        # Insert after the last include in the header
        last_include = matches[-1]
        insert_pos = last_include.end()
        content = content[:insert_pos] + extern_block + content[insert_pos:]
    else:
        # Fallback: insert after the copyright header
        content = extern_block + '\n' + content

    # 2. Patch ComputeViewMatrix to add the WebXR override
    # Find the function and add the override at the very start
    old_func_start = 'void ComputeViewMatrix( VMatrix *pViewMatrix, const Vector &origin, const QAngle &angles )\n{'

    override_code = '''void ComputeViewMatrix( VMatrix *pViewMatrix, const Vector &origin, const QAngle &angles )
{
#ifdef __EMSCRIPTEN__
	if ( g_bWebXRMatrixActive )
	{
		// WebXR override: copy column-major [16] into VMatrix m[row][col]
		// WebXR transform.matrix is column-major: element(row,col) = matrix[col*4+row]
		for ( int row = 0; row < 4; row++ )
		{
			for ( int col = 0; col < 4; col++ )
			{
				(*pViewMatrix)[row][col] = g_WebXRViewMatrix[col * 4 + row];
			}
		}
		return;
	}
#endif
	// --- Original ComputeViewMatrix below ---'''

    if old_func_start in content:
        content = content.replace(old_func_start, override_code, 1)
    else:
        print(f"  webxr_glmain: WARNING could not find ComputeViewMatrix signature")
        return

    with open(filepath, 'w') as f:
        f.write(content)
    print(f"  webxr_glmain: patched ComputeViewMatrix + extern declarations")
