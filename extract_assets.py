from pathlib import Path
import struct,re,json,sys
sys.stdout.reconfigure(encoding='utf-8',errors='replace')
b=Path('work/build_inputs/original_installation/小映批量助手.exe').read_bytes()
u16=lambda o:struct.unpack_from('<H',b,o)[0]
u32=lambda o:struct.unpack_from('<I',b,o)[0]
pe=u32(60); opt=pe+24; base=struct.unpack_from('<Q',b,opt+24)[0]
sections=[]
for i in range(u16(pe+6)):
 o=opt+u16(pe+20)+i*40
 name=b[o:o+8].rstrip(b'\0').decode(); vs,va,rs,raw=struct.unpack_from('<IIII',b,o+8)
 sections.append((name,va,vs,raw,rs))
print('Image base',hex(base),'sections',sections)
def vaoff(v):
 r=v-base
 for name,va,vs,raw,rs in sections:
  if va<=r<va+rs:return raw+r-va
 return None
def offva(o):
 for name,va,vs,raw,rs in sections:
  if raw<=o<raw+rs:return base+va+o-raw
 return None
out=Path('work/extracted');out.mkdir(exist_ok=True)
found=[]
for m in re.finditer(rb'(?:frontend/)?dist/(?:assets/)?[A-Za-z0-9_.@/-]+\.(?:js|css|html)',b):
 name=m.group().decode(); ptr=offva(m.start())
 if ptr is None:continue
 for ref in re.finditer(re.escape(struct.pack('<Q',ptr)),b):
  o=ref.start()
  if o+48>len(b):continue
  np,nl,dp,dl=struct.unpack_from('<QQQQ',b,o)
  if nl!=len(name) or dl>20_000_000:continue
  do=vaoff(dp)
  if do is None:continue
  data=b[do:do+dl]
  if not data or b'\x00' in data[:300]:continue
  if not any(x['name']==name for x in found):
   target=out/name.replace('/','__');target.write_bytes(data)
   found.append({'name':name,'file':str(target),'offset':do,'length':dl,'entry':o})
print('EMBEDDED',json.dumps(found,ensure_ascii=False,indent=2))
Path('work/embedded_manifest.json').write_text(json.dumps({'base':base,'files':found},ensure_ascii=False,indent=2),encoding='utf-8')
for term in [b'<html',b'<!doctype',b'<!DOCTYPE',b'assets/index-',b'function createApp',b'__vite']:
 hits=[m.start() for m in re.finditer(re.escape(term),b)]
 print(term.decode(),hits[:15], 'total',len(hits))
