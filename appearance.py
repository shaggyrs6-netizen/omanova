"""Save appearance separately from private observing settings; no worker restart."""
import argparse
import json
import os
from pathlib import Path
import tempfile

def save(directory,mode):
    if mode not in ('desktop','observatory'):raise ValueError('Unknown appearance mode')
    os.umask(0o077);directory.mkdir(mode=0o700,parents=True,exist_ok=True)
    with tempfile.NamedTemporaryFile(mode='w',dir=directory,prefix='.appearance-',delete=False) as stream:
        json.dump({'schema':1,'mode':mode},stream);stream.write('\n');temporary=Path(stream.name)
    temporary.replace(directory/'appearance.json')

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--state',type=Path,required=True);parser.add_argument('--mode',choices=('desktop','observatory'),required=True);args=parser.parse_args()
    try:save(args.state,args.mode)
    except OSError:raise SystemExit('Could not save appearance settings')
