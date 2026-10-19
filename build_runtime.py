from pathlib import Path
import json,subprocess,sys,re
from urllib.parse import urlparse
sys.stdout.reconfigure(encoding='utf-8')
config=json.loads(Path('work/release_config.json').read_text(encoding='utf-8'))
assert re.fullmatch(r'\d+\.\d+\.\d+',config['version'])
url=config.get('manifestUrl','')
if url:
 u=urlparse(url);assert u.scheme=='https' and u.netloc and not u.username
repo=config.get('githubRepository','')
assert not repo or re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9][A-Za-z0-9._-]*',repo)
asset=config.get('assetName','YuandianToolbox.exe')
assert asset.endswith('.exe') and '/' not in asset and chr(92) not in asset
settings=Path('work/ReleaseSettings.cs').resolve()
settings.write_text('static class ReleaseSettings { public const string Version = '+json.dumps(config['version'])+'; public const string ManifestUrl = '+json.dumps(url)+'; public const string GithubRepository = '+json.dumps(repo)+'; public const string AssetName = '+json.dumps(asset)+'; }',encoding='utf-8')
output=Path('work/build_inputs/runtime_payload/元点剪辑批量工具箱.exe').resolve()
args=['C:/Windows/Microsoft.NET/Framework64/v4.0.30319/csc.exe','/nologo','/codepage:65001','/target:winexe','/platform:x64','/optimize+','/reference:System.Drawing.dll','/reference:System.Web.Extensions.dll','/reference:System.Windows.Forms.dll','/out:'+str(output)]+[str(Path('work/'+n).resolve()) for n in ['LocalLauncher.cs','SilenceProcessor.cs','MaterialCollector.cs','DraftPreview.cs','UpdateService.cs','UpdateInstaller.cs','ReleaseSettings.cs']]
r=subprocess.run(args,capture_output=True,creationflags=subprocess.CREATE_NO_WINDOW)
assert r.returncode==0,r.stdout.decode(errors='replace')+r.stderr.decode(errors='replace')
print('Runtime built; release version '+config['version']+'; online update configured: '+str(bool(url or repo)))
