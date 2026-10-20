"""Build the open-source customization layer. Never reads a personal draft directory."""
from pathlib import Path
import argparse, hashlib, json, os, shutil, subprocess, sys
ROOT=Path(__file__).resolve().parent
SOURCES=['export_diagnostics.js','test_export_start.cjs','LocalLauncher.cs','SilenceProcessor.cs','breath_tools.js','test_export_policies.cjs','ExportSmoke.cs','MaterialCollector.cs','DraftPreview.cs','UpdateService.cs','UpdateInstaller.cs','SingleFileBootstrap.cs','AutoUpdateWorker.cs','local_runtime.js','update_ui.js','studio_design.js','draft_preview.js','studio_theme.css','branded_index.html','patch_frontend.cjs','build_runtime.py','build_binary.py','build_single_file.py','extract_assets.py','verify_build.py','release_config.json','test_cover_frontend.cjs','test_install_frontend.cjs','PreviewSmoke.cs']
ORIGINAL_SHA256='016012b4a179f428cc90e2b2520c761606bb773c572803abd0fb6f64485785ee'
RESOURCES=['bravo.exe','f2.exe','ffmpeg.exe','MediaInfo.exe','qcore_ext.dll','uptool.exe']
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 parser=argparse.ArgumentParser(description=__doc__)
 parser.add_argument('--check',action='store_true',help='Compile the open managed helper and run JS unit tests without original binaries')
 parser.add_argument('--original-dir',type=Path,help='Original compatible installation containing the original EXE and Resources')
 parser.add_argument('--zig',default='zig',help='Zig 0.13 compiler executable')
 parser.add_argument('--node',default='node',help='Node executable name or absolute path')
 args=parser.parse_args()
 if os.name!='nt':parser.error('Windows x64 and .NET Framework 4.x compiler are required')
 node=shutil.which(args.node)
 if not node:parser.error('Node.js was not found. Install it or pass --node PATH')
 if not args.check:
  if not args.original_dir:parser.error('Full build requires --original-dir')
  original=args.original_dir.resolve()/'小映批量助手.exe'
  if not original.is_file() or digest(original)!=ORIGINAL_SHA256:parser.error('Unsupported original EXE: expected SHA-256 '+ORIGINAL_SHA256)
  for name in RESOURCES:
   if not (args.original_dir/'Resources'/name).is_file():parser.error('Missing supplied resource: '+name)
 stage=ROOT/'.build';work=stage/'work';work.mkdir(parents=True,exist_ok=True)
 for name in SOURCES+['draft_codec.c','build_codec.py','test_draft_codec.py','test_direct_export.cjs','test_export_component.cjs','test_draft_export_component.cjs','ExportEnvironment.cs','ExportEnvironmentSmoke.cs','test_default_export_path.cjs']:shutil.copy2(ROOT/name,work/name)
 (work/'acorn').mkdir(exist_ok=True)
 shutil.copy2(ROOT/'acorn.js',work/'acorn/acorn.js');shutil.copy2(ROOT/'LICENSE-ACORN',work/'acorn/LICENSE')
 payload=work/'build_inputs/runtime_payload';payload.mkdir(parents=True,exist_ok=True)
 (stage/'outputs').mkdir(exist_ok=True)
 def run(command):
  result=subprocess.run(command,cwd=stage,capture_output=True,creationflags=subprocess.CREATE_NO_WINDOW)
  print(result.stdout.decode("utf-8",errors="replace"),end="");print(result.stderr.decode("utf-8",errors="replace"),end="")
  result.check_returncode()
 resources=payload/'Resources/Core/Resources';resources.mkdir(parents=True,exist_ok=True)
 run([sys.executable,'work/build_codec.py','--zig',args.zig,'--output',str(resources/'jydraft_bridge.dll')])
 run([sys.executable,'work/test_draft_codec.py',str(resources/'jydraft_bridge.dll')])
 run([node,'work/test_direct_export.cjs']);run([node,'work/test_export_start.cjs']);run([node,'work/test_export_policies.cjs']);run([node,'work/test_cover_frontend.cjs']);run([node,'work/test_install_frontend.cjs']);run([node,'work/test_default_export_path.cjs'])
 run([sys.executable,'work/build_runtime.py'])
 csc=str(Path(os.environ.get('WINDIR','C:/Windows'))/'Microsoft.NET/Framework64/v4.0.30319/csc.exe')
 environmentprobe=stage/'ExportEnvironmentSmoke.exe'
 run([csc,'/nologo','/codepage:65001','/target:exe','/platform:x64','/out:'+str(environmentprobe)]+[str(work/n) for n in ['ExportEnvironmentSmoke.cs','ExportEnvironment.cs']])
 run([str(environmentprobe)])
 probe=stage/'PreviewSmoke.exe'
 run([csc,'/nologo','/codepage:65001','/target:exe','/platform:x64','/reference:System.Drawing.dll','/reference:System.Web.Extensions.dll','/out:'+str(probe)]+[str(work/n) for n in ['PreviewSmoke.cs','DraftPreview.cs','MaterialCollector.cs']])
 run([str(probe)])
 exportprobe=stage/'ExportSmoke.exe'
 run([csc,'/nologo','/codepage:65001','/target:exe','/platform:x64','/main:ExportSmoke','/reference:System.Drawing.dll','/reference:System.Windows.Forms.dll','/reference:System.Web.Extensions.dll','/out:'+str(exportprobe)]+[str(work/n) for n in ['ExportSmoke.cs','LocalLauncher.cs','ExportEnvironment.cs','SilenceProcessor.cs','MaterialCollector.cs','DraftPreview.cs','UpdateService.cs','UpdateInstaller.cs','ReleaseSettings.cs']])
 run([str(exportprobe)])
 if args.check:
  print('PASS: managed helper compiled; cover and update tests passed. Original editor integration was not built.');return
 target=work/'build_inputs/original_installation';target.mkdir(parents=True,exist_ok=True);shutil.copy2(original,target/original.name)
 resources=payload/'Resources/Core/Resources';resources.mkdir(parents=True,exist_ok=True)
 expected=set(RESOURCES+['jydraft_bridge.dll'])
 extras=[p.name for p in resources.iterdir() if p.name not in expected]
 if extras:raise RuntimeError('Unexpected staging files; use a fresh checkout: '+repr(extras))
 for name in RESOURCES:shutil.copy2(args.original_dir/'Resources'/name,resources/name)
 run([sys.executable,'work/extract_assets.py']);run([node,'work/patch_frontend.cjs']);run([node,'work/test_export_component.cjs']);run([node,'work/test_draft_export_component.cjs']);run([sys.executable,'work/build_binary.py']);run([sys.executable,'work/verify_build.py']);run([sys.executable,'work/build_single_file.py'])
 package=stage/'outputs/元点剪辑批量工具箱.exe'
 run([str(package),'--verify-package',str(work/'package-verification.json')])
 if digest(original)!=ORIGINAL_SHA256:raise RuntimeError('Original input changed during build')
 output=ROOT/'outputs';output.mkdir(exist_ok=True);shutil.copy2(package,output/package.name)
 print(json.dumps({'output':str(output/package.name),'sha256':digest(package),'original_input_unchanged':True},ensure_ascii=False,indent=2))
if __name__=='__main__':
 sys.stdout.reconfigure(encoding='utf-8');main()
