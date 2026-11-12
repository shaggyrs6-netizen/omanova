"""Explicit city/postcode lookup. Query is read from stdin, never argv."""
import json
from math import isfinite
import sys
from urllib.parse import urlencode
from worker import get_json


def search(query, fetch=get_json):
    if not isinstance(query,str) or not 2<=len(query.strip())<=120 or any(ord(c)<32 for c in query):
        raise ValueError('Enter a city or postcode (2–120 characters)')
    payload=fetch('https://geocoding-api.open-meteo.com/v1/search?'+urlencode(
        {'name':query.strip(),'count':8,'language':'en','format':'json'}),max_bytes=65536)
    rows=payload.get('results',[]) if isinstance(payload,dict) else None
    if not isinstance(rows,list) or len(rows)>8: raise ValueError('Unexpected lookup response')
    result=[]
    for row in rows:
        try:
            lat=float(row['latitude']);lon=float(row['longitude']);elevation=float(row.get('elevation',0))
            if not all(map(isfinite,(lat,lon,elevation))) or not -90<=lat<=90 or not -180<=lon<=180 or not -500<=elevation<=9000: continue
            name=' '.join(str(row['name']).split())[:48]
            label=', '.join(str(row.get(k,''))[:80] for k in ('name','admin1','country') if row.get(k))
            result.append({'name':name,'label':label,'lat':lat,'lon':lon,'elevation':elevation})
        except (KeyError,ValueError,TypeError): continue
    return result


if __name__=='__main__':
    try:
        raw=sys.stdin.buffer.readline(1025)
        if len(raw)>1024 or not raw.endswith(b'\n'): raise ValueError('Invalid query')
        print(json.dumps(search(json.loads(raw))))
    except Exception:
        # No request URLs or supplied query in process diagnostics.
        print('Place lookup unavailable. Check the connection or use manual coordinates.',file=sys.stderr)
        sys.exit(1)
