f = 'src/translation-layer-next/husk-tl-jni-more.c'
s = open(f, encoding='utf-8').read()

start = s.find('static void Surf_init_tex')
end = s.find('/* WindowManager.LayoutParams */')
assert start > 0 and end > start, (start, end)

# find the beginning of the comment block that precedes Surf_init_tex
cstart = s.rfind('/* ---- SurfaceView / SurfaceHolder / GLSurfaceView ----', 0, start)
# Surf_init_tex comes first; the big comment comes after it. Block spans from
# Surf_init_tex through the GLSV functions, ending before the WLP comment.
block = s[start:end]
open('.svblock.c', 'w', encoding='utf-8').write(block)
rest = s[:start] + s[end:]

# destination: after the BM_compress line (before the Canvas section comment)
dst = rest.find('static void BM_compress(tl_jcall *c) { (void)c; c->ret = vz(0); }')
assert dst > 0
nl = rest.find('\n', dst)
rest = rest[:nl + 1] + '\n' + block + rest[nl + 1:]
open(f, 'w', encoding='utf-8').write(rest)
print('moved', block.count('\n'), 'lines')
