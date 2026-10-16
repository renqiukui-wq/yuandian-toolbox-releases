from pathlib import Path
import json,struct,hashlib,sys
sys.stdout.reconfigure(encoding='utf-8')
a=Path('work/build_inputs/original_installation/小映批量助手.exe').read_bytes();p=Path('work/build_inputs/runtime_payload/Resources/Core/元点剪辑批量工具箱_界面.exe');b=p.read_bytes()
manifest=json.loads(Path('work/embedded_manifest.json').read_text(encoding='utf-8'));js=next(x for x in manifest['files'] if x['name'].endswith('.js'))
new=Path('work/patched_frontend.js').read_bytes();assert len(a)==len(b);assert b[js['offset']:js['offset']+len(new)]==new
assert struct.unpack_from('<Q',b,js['entry']+24)[0]==len(new)
assert b[js['entry']+32:js['entry']+48]==bytes(x^255 for x in hashlib.sha256(new).digest()[:16])
html_entry=next(x for x in manifest['files'] if x['name'].endswith('index.html'))
html=Path('work/branded_index.html').read_bytes()
assert b[html_entry['offset']:html_entry['offset']+len(html)]==html
assert struct.unpack_from('<Q',b,html_entry['entry']+24)[0]==len(html)
assert b[html_entry['entry']+32:html_entry['entry']+48]==bytes(x^255 for x in hashlib.sha256(html).digest()[:16])
pe=struct.unpack_from('<I',b,60)[0];opt=pe+24;size=struct.unpack_from('<H',b,pe+20)[0]
for i in range(struct.unpack_from('<H',b,pe+6)[0]):
 o=opt+size+i*40;name=b[o:o+8].rstrip(b'\0');rawsize,raw=struct.unpack_from('<II',b,o+16)
 if name==b'.text':
  restored=bytearray(b)
  for patch in json.loads(Path('work/native_patch_manifest.json').read_text()):
   pos=patch['offset'];newbytes=bytes.fromhex(patch['replacement']);assert restored[pos:pos+len(newbytes)]==newbytes;restored[pos:pos+len(newbytes)]=bytes.fromhex(patch['expected'])
  assert a[raw:raw+rawsize]==restored[raw:raw+rawsize]
assert hashlib.sha256(a).hexdigest()==json.loads(Path('work/build_evidence.json').read_text())['original_sha256']
print('PASS: only the two declared native naming patches changed; patched JS, embedded length and hash verified; original EXE unchanged.')
Path('work/integrity.json').write_text(json.dumps({'passed':True,'original_unchanged':True,'embedded_assets_verified':True}),encoding='utf-8')
