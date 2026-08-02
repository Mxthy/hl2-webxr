// C-linkage stubs for IVP symbols with mismatched WASM signatures
void _ZN27IVP_Mindist_Minimize_Solver23init_mms_function_tableEv(void) {}

// IVP_Compact_Edge::next_table — weak data symbol required by side modules.
// The table is only used as an address-resolved lookup by the WebAssembly
// dynamic linker; zero-initialized entries preserve safe behavior for the
// unsupported native IVP path.
__attribute__((weak, used, visibility("default")))
void* _ZN16IVP_Compact_Edge10next_tableE[256] = { 0 };
