"""Save appearance separately from private observing settings; no worker restart."""
import argparse
import json
import os
from pathlib import Path
import tempfile

def save(directory,mode,observing=None):
    if mode not in ('desktop','observatory'):raise ValueError('Unknown appearance mode')
    existing={}
    try:existing=json.loads((directory/'appearance.json').read_text())
    except (OSError,ValueError):pass
    if not isinstance(existing,dict):existing={}
    observing=observing if observing is not None else existing.get('observing','normal')
    if observing not in ('normal','dim','red'):raise ValueError('Unknown observing display')
    data={'schema':1,'mode':mode}
    if observing!='normal':data['observing']=observing
    os.umask(0o077);directory.mkdir(mode=0o700,parents=True,exist_ok=True)
    with tempfile.NamedTemporaryFile(mode='w',dir=directory,prefix='.appearance-',delete=False) as stream:
        json.dump(data,stream);stream.write('\n');temporary=Path(stream.name)
    temporary.replace(directory/'appearance.json')

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--state',type=Path,required=True);parser.add_argument('--mode',choices=('desktop','observatory'),required=True);parser.add_argument('--observing',choices=('normal','dim','red'));args=parser.parse_args()
    try:save(args.state,args.mode,args.observing)
    except OSError:raise SystemExit('Could not save appearance settings')
