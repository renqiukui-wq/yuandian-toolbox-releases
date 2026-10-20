"""Compile the local Windows draft codec from source with Zig 0.13+."""
from pathlib import Path
import argparse, subprocess
def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--zig",default="zig")
    parser.add_argument("--output",type=Path,required=True)
    args=parser.parse_args()
    args.output.parent.mkdir(parents=True,exist_ok=True)
    subprocess.run([args.zig,"cc","-target","x86_64-windows-gnu","-shared","-O2","-s",
                    str(Path(__file__).with_name("draft_codec.c")),"-o",str(args.output),
                    "-lbcrypt","-lcrypt32"],check=True)
    # This runtime loads exports dynamically and does not ship the import library.
    import_library=args.output.parent/"draft_codec.lib"
    if import_library.is_file():import_library.unlink()
if __name__=="__main__":main()
