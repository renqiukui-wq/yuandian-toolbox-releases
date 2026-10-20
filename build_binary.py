from pathlib import Path
import json,struct,hashlib,shutil
source=Path('work/build_inputs/original_installation/小映批量助手.exe')
b=bytearray(source.read_bytes());manifest=json.loads(Path('work/embedded_manifest.json').read_text(encoding='utf-8'))
a=next(x for x in manifest['files'] if x['name'].endswith('.js'))
new=Path('work/patched_frontend.js').read_bytes()
assert len(new)<=a['length']
old=bytes(b[a['offset']:a['offset']+a['length']]);old_hash=bytes(b[a['entry']+32:a['entry']+48])
assert old_hash==bytes(x^255 for x in hashlib.sha256(old).digest()[:16]), 'Unexpected embed file hash'
# Use the existing allocated span. Function tables, imports, and offsets do not change.
b[a['offset']:a['offset']+a['length']]=new+b' '*(a['length']-len(new))
struct.pack_into('<Q',b,a['entry']+24,len(new));b[a['entry']+32:a['entry']+48]=bytes(x^255 for x in hashlib.sha256(new).digest()[:16])
html_entry=next(x for x in manifest['files'] if x['name'].endswith('index.html'))
html=Path('work/branded_index.html').read_bytes()
assert len(html)<=html_entry['length']
old_html=bytes(b[html_entry['offset']:html_entry['offset']+html_entry['length']])
assert bytes(b[html_entry['entry']+32:html_entry['entry']+48])==bytes(x^255 for x in hashlib.sha256(old_html).digest()[:16])
b[html_entry['offset']:html_entry['offset']+html_entry['length']]=html+b' '*(html_entry['length']-len(html))
struct.pack_into('<Q',b,html_entry['entry']+24,len(html))
b[html_entry['entry']+32:html_entry['entry']+48]=bytes(x^255 for x in hashlib.sha256(html).digest()[:16])
pe=struct.unpack_from('<I',b,60)[0];struct.pack_into('<I',b,pe+24+64,0)
native_patches=[
 {'offset':7779844,'expected':'4d85c0','replacement':'4d31c0','reason':'always use timeline name instead of custom prefix'},
 {'offset':7780071,'expected':'e814d78fff48','replacement':'4883c4585dc3','reason':'return sanitized timeline name before draft-name concatenation'}
]
for patch in native_patches:
 o=patch['offset'];expected=bytes.fromhex(patch['expected']);replacement=bytes.fromhex(patch['replacement'])
 assert bytes(b[o:o+len(expected)])==expected,'Unexpected native function bytes'
 assert len(expected)==len(replacement);b[o:o+len(expected)]=replacement
Path('work/native_patch_manifest.json').write_text(json.dumps(native_patches,indent=2),encoding='utf-8')
# Replace the old editor-dependent bridge in its existing Go byte-slice span.
# Preserve the allocation length; a PE DLL permits zero overlay bytes.
codec=Path('work/build_inputs/runtime_payload/Resources/Core/Resources/jydraft_bridge.dll').read_bytes()
offset,length=24561376,15441121
assert hashlib.sha256(b[offset:offset+length]).hexdigest()=='f5b940fad5508e692f5d8b5869f4350753d8e4995252c1bbd0c5a04dfe89b416'
assert codec[:2]==b'MZ' and len(codec)<length
b[offset:offset+length]=codec+b'\0'*(length-len(codec))
cache_offsets=[12024518,12285823]
for pos in cache_offsets:
 assert b[pos:pos+18]==b'jydraft_bridge.dll'
 b[pos:pos+18]=b'ydcodec_bridge.dll'
Path('work/codec_patch_manifest.json').write_text(json.dumps({'offset':offset,'length':length,'codec_length':len(codec),'sha256':hashlib.sha256(codec).hexdigest(),'cache_offsets':cache_offsets}),encoding='utf-8')
out=Path('work/build_inputs/runtime_payload/Resources/Core');out.mkdir(parents=True,exist_ok=True)
(out/'元点剪辑批量工具箱_界面.exe').write_bytes(b)
Path('work/build_evidence.json').write_text(json.dumps({'original_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'modified_sha256':hashlib.sha256(b).hexdigest(),'original_bytes':len(b),'changed_region':'embedded frontend JS and branded HTML + embed lengths/hashes + PE checksum + 9 bytes in timelineOutputName + embedded draft codec and cache filename','source_not_modified':True},ensure_ascii=False,indent=2),encoding='utf-8')
print('Built executable; original unchanged; runtime payload UI updated.')

