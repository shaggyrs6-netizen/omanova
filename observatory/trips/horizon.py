"""Manual true-bearing obstruction sectors. No terrain or device sensing."""
from math import isfinite
import numpy as np


def validate(sectors):
    if not isinstance(sectors,list) or len(sectors)>32:
        raise ValueError('Use at most 32 horizon obstructions per place')
    output=[]
    for item in sectors:
        if not isinstance(item,dict):raise ValueError('Invalid horizon obstruction')
        name=' '.join(str(item.get('name','')).split())
        try:start,end,height=(float(item[k]) for k in ('from','to','height'))
        except (KeyError,ValueError,TypeError):raise ValueError('Enter a bearing range and height') from None
        if not name or len(name)>48 or not all(map(isfinite,(start,end,height))):raise ValueError('Give each obstruction a short name and finite angles')
        if not 0<=start<360 or not 0<=end<=360 or not 0<=height<=90 or start==end:
            raise ValueError('Bearings must be 0–360°, with different start/end; height must be 0–90°')
        output.append({'name':name,'from':start,'to':end,'height':height})
    return output


def altitude(bearing,sectors):
    angle=np.asarray(bearing,dtype=float)%360
    height=np.zeros_like(angle)
    for sector in sectors:
        start,end=sector['from'],sector['to']
        inside=(angle>=start)&(angle<=end) if start<end else (angle>=start)|(angle<=end)
        height=np.where(inside,np.maximum(height,sector['height']),height)
    return height


def place_key(place):
    return f"{float(place['lat']):.6f},{float(place['lon']):.6f},{float(place.get('elevation',0)):.1f}"
