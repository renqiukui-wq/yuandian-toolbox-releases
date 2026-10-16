from pathlib import Path
import json,hashlib,zipfile,subprocess,sys

sys.stdout.reconfigure(encoding='utf-8')
root=Path('work/build_inputs/runtime_payload').resolve()
entries=[]
for p in sorted(root.rglob('*')):
 if p.is_file():entries.append({'path':p.relative_to(root).as_posix(),'size':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
assert len(entries)==9
version=hashlib.sha256(json.dumps(entries,ensure_ascii=False,sort_keys=True).encode()).hexdigest()
manifest=Path('work/single_file_manifest.json').resolve()
manifest.write_text(json.dumps({'version':version,'files':entries},ensure_ascii=False),encoding='utf-8')
payload=Path('work/single_file_payload.zip').resolve()
with zipfile.ZipFile(payload,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=6) as z:
 for entry in entries:z.write(root/entry['path'],entry['path'])
output=Path('outputs/元点剪辑批量工具箱.exe').resolve()
command=[r'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe','/nologo','/codepage:65001','/target:winexe','/platform:x64','/optimize+',
 '/reference:System.Web.Extensions.dll','/reference:System.Windows.Forms.dll','/reference:System.IO.Compression.dll','/reference:System.IO.Compression.FileSystem.dll',
 '/out:'+str(output),'/resource:'+str(manifest)+',Bundle.Manifest','/resource:'+str(payload)+',Bundle.Payload',str(Path('work/SingleFileBootstrap.cs').resolve()),str(Path('work/AutoUpdateWorker.cs').resolve())]
result=subprocess.run(command,capture_output=True,creationflags=subprocess.CREATE_NO_WINDOW)
if result.returncode:
 print(result.stdout.decode('utf-8',errors='replace'))
 print(result.stderr.decode('utf-8',errors='replace'))
 raise RuntimeError('Single file compilation failed')
evidence={'version':version,'files':len(entries),'exe_bytes':output.stat().st_size,'exe_sha256':hashlib.sha256(output.read_bytes()).hexdigest()}
Path('work/single_file_build.json').write_text(json.dumps(evidence,indent=2),encoding='utf-8')
print(json.dumps(evidence,indent=2))
