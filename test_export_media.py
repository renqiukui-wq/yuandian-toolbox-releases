from pathlib import Path
import subprocess,json,hashlib,sys
import argparse
parser=argparse.ArgumentParser();parser.add_argument('--resources',required=True);opts=parser.parse_args()
ROOT=Path(__file__).resolve().parent
RES=Path(opts.resources)
import time
TEST=ROOT/'.build/export-media-tests'/str(time.time_ns());TEST.mkdir(parents=True)
EXE=ROOT/'.build/ExportSmoke.exe'
def run(args,ok=True):
 p=subprocess.run([str(x) for x in args],capture_output=True,creationflags=subprocess.CREATE_NO_WINDOW)
 if ok and p.returncode:raise RuntimeError(p.stdout.decode('utf-8','replace')+p.stderr.decode('utf-8','replace'))
 return p
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def meta(p):return json.loads(run([RES/'MediaInfo.exe','--Output=JSON',p]).stdout)['media']['track']
def fixture(name,size='640x360',duration='0.5',audio='tone'):
 p=TEST/(name+'.mp4');cmd=[RES/'ffmpeg.exe','-hide_banner','-loglevel','error','-y','-f','lavfi','-i',f'testsrc2=size={size}:rate=30:duration={duration}']
 if audio!='none':
  expr='0' if audio=='silent' else 'if(between(t,1,2),0,0.3*sin(2*PI*440*t))' if audio=='gap' else '0.3*sin(2*PI*440*t)'
  cmd+=['-f','lavfi','-i',f'aevalsrc={expr}:s=48000:d={duration}'] if audio!='gap' else ['-f','lavfi','-i',f"aevalsrc='{expr}':s=48000:d={duration}"]
 cmd+=['-c:v','libx264','-preset','ultrafast','-threads','2','-pix_fmt','yuv420p','-c:a','aac',p];run(cmd);return p
def convert(p,mode,cut=False,cover='first',fail=False):
 out=TEST/(p.stem+'-'+mode+'-'+str(cut)+'-'+cover);out.mkdir(exist_ok=True)
 before=sha(p);r=run([EXE,RES,p,out,mode,str(cut).lower(),cover],ok=not fail);assert sha(p)==before,'input modified'
 result=out/p.name
 if fail:assert r.returncode and not result.exists();return {'case':out.name,'guard':'passed'}
 assert sorted(x.name for x in out.iterdir())==[p.name],list(out.iterdir())
 tracks=meta(result);v=next(t for t in tracks if t['@type']=='Video');return {'case':out.name,'width':int(v['Width']),'height':int(v['Height']),'duration':float(v['Duration']),'audio':any(t['@type']=='Audio' for t in tracks),'identical':sha(result)==before}
results=[]
for name,size,mode,expected in [('same720','1280x720','auto720',(1280,720)),('sameportrait','720x1280','auto720',(720,1280)),('fullhd','1920x1080','auto1080',(1920,1080)),('up2k','360x640','auto1440',(1440,2560)),('up4k','640x360','auto2160',(3840,2160)),('down','1920x1080','auto720',(1280,720))]:
 r=convert(fixture(name,size),mode);print(json.dumps(r),flush=True);assert (r['width'],r['height'])==expected;assert r['audio'];
 if name in ['same720','sameportrait','fullhd']:assert r['identical'],'matching size reencoded'
 results.append(r)
p=fixture('gap',duration='3',audio='gap');r=convert(p,'auto720',True);assert 2.08<r['duration']<2.3 and r['audio'];results.append(r)
r=convert(p,'auto720',True,'random');assert 2.08<r['duration']<2.3 and r['audio'];results.append(r)
p=fixture('noaudio','1280x720',audio='none');r=convert(p,'auto720',True);assert r['identical'];results.append(r)
p=fixture('silence',duration='2',audio='silent');results.append(convert(p,'auto720',True,fail=True))
out=TEST/'batch-isolation';out.mkdir();good=fixture('batchgood',size='1280x720');bad=fixture('batchbad',duration='2',audio='silent')
r=run([EXE,RES,bad,out,'auto720','true','first',good],ok=False)
assert r.returncode and (out/good.name).exists() and not (out/bad.name).exists(),'bad input stopped good input'
assert sha(out/good.name)==sha(good)
results.append({'case':'batch-isolation','guard':'passed'})
(TEST/'results.json').write_text(json.dumps(results,indent=2),encoding='utf-8');print(json.dumps(results,indent=2))
