"""Bounded, opt-in Skadi terrain estimates. No personal coordinates leave this process.
Only coarse 1-degree tile identifiers are requested from the provider.
"""
from datetime import datetime, timezone
import gzip
import hashlib
import io
import json
import math
from pathlib import Path
import time
from urllib.request import Request, urlopen
import numpy as np

RADIUS = 6371008.8
RANGE_M = 50000
BEARINGS = np.arange(720) / 2
DISTANCES = np.arange(100, RANGE_M + 1, 100)
GRID = 3601
RAW_LIMIT = GRID * GRID * 2
DOWNLOAD_LIMIT = 32 * 1024 * 1024
SOURCE = 'Mapzen / Tilezen Terrain Tiles (Skadi), hosted on AWS'
SOURCE_URL = 'https://registry.opendata.aws/terrain-tiles/'
CREDITS_URL = 'https://github.com/tilezen/joerd/blob/master/docs/attribution.md'
MODEL = 'skadi-spherical-50km-v1'


def observing_height(value):
    try: value = float(value)
    except (TypeError, ValueError): raise ValueError('Enter observing height above ground in metres') from None
    if not math.isfinite(value) or not 0 <= value <= 100:
        raise ValueError('Observing height must be between 0 and 100 metres above ground')
    return value


def profile_key(place):
    text = f"{MODEL}:{float(place['lat']):.8f}:{float(place['lon']):.8f}:{observing_height(place.get('observingHeight',1.7)):.3f}"
    return hashlib.sha256(text.encode()).hexdigest()


def tile_id(lat, lon):
    return f"{'N' if lat >= 0 else 'S'}{abs(lat):02d}{'E' if lon >= 0 else 'W'}{abs(lon):03d}"


def decode(blob):
    try:
        with gzip.GzipFile(fileobj=io.BytesIO(blob)) as stream:
            raw = stream.read(RAW_LIMIT + 1)
    except (OSError, EOFError): raise ValueError('Terrain tile is damaged; no horizon applied') from None
    if len(raw) != RAW_LIMIT: raise ValueError('Unexpected terrain grid size; no horizon applied')
    return np.frombuffer(raw, dtype='>i2').reshape(GRID, GRID)


def download_tile(lat, lon, cache, allowed, deadline):
    name = tile_id(lat, lon)
    path = cache / (name + '.hgt.gz')
    if path.exists():
        if path.stat().st_size > DOWNLOAD_LIMIT: raise ValueError('Terrain cache is oversized')
        return decode(path.read_bytes())
    if not allowed: raise ValueError('Terrain not cached. Enable the one-time download, then estimate again.')
    if time.monotonic() >= deadline: raise ValueError('Terrain download time limit reached; retry to use already cached tiles')
    url = f'https://s3.amazonaws.com/elevation-tiles-prod/skadi/{name[:3]}/{name}.hgt.gz'
    try:
        req = Request(url, headers={'User-Agent': 'OMANOVA/0.1.2 terrain-preview'})
        with urlopen(req, timeout=min(30, max(1, deadline-time.monotonic()))) as response:
            if response.geturl() != url: raise ValueError('Unexpected terrain download redirect')
            chunks = []; total = 0
            while True:
                if time.monotonic() > deadline: raise ValueError('Terrain download time limit reached')
                chunk = response.read(65536)
                if not chunk: break
                total += len(chunk)
                if total > DOWNLOAD_LIMIT: raise ValueError('Terrain download exceeds size limit')
                chunks.append(chunk)
            blob = b''.join(chunks)
    except OSError: raise ValueError('Terrain provider unavailable or coverage missing. Manual obstructions were kept.') from None
    grid = decode(blob)
    cache.mkdir(mode=0o700, parents=True, exist_ok=True)
    temporary = path.with_suffix('.tmp')
    temporary.write_bytes(blob); temporary.chmod(0o600); temporary.replace(path)
    return grid


def ray_points(lat, lon):
    phi, lam = np.radians([lat, lon]); bearing = np.radians(BEARINGS[:,None]); delta = DISTANCES[None,:] / RADIUS
    p = np.arcsin(np.sin(phi)*np.cos(delta) + np.cos(phi)*np.sin(delta)*np.cos(bearing))
    l = lam + np.arctan2(np.sin(bearing)*np.sin(delta)*np.cos(phi), np.cos(delta)-np.sin(phi)*np.sin(p))
    return np.degrees(p), (np.degrees(l)+180)%360-180


def sample_grid(grid, lat, lon, south, west):
    row = np.clip(np.rint((south+1-lat)*(GRID-1)).astype(int),0,GRID-1)
    col = np.clip(np.rint((lon-west)*(GRID-1)).astype(int),0,GRID-1)
    values = grid[row,col].astype(float)
    if np.any((values < -12000) | (values > 9000)):
        raise ValueError('Terrain has missing or invalid heights. No partial skyline applied; manual obstructions were kept.')
    return values


def angles(heights, ground, observer_height, distances=DISTANCES):
    delta = np.asarray(distances) / RADIUS
    y = (RADIUS + heights)*np.cos(delta) - (RADIUS + ground + observer_height)
    x = (RADIUS + heights)*np.sin(delta)
    return np.degrees(np.arctan2(y,x))


def load_profile(place, state):
    path = state/'terrain/profiles'/(profile_key(place)+'.json')
    if not path.exists(): return None
    if path.stat().st_size > 100000: raise ValueError('Terrain profile is oversized')
    try:
        profile = json.loads(path.read_text())
        samples = profile['samples']
        if profile['key'] != profile_key(place) or profile['model'] != MODEL or len(samples) != 720:
            raise ValueError('Terrain profile does not match this observing point')
        if any(type(x) not in (int,float) or not math.isfinite(x) or not 0<=x<=90 for x in samples):
            raise ValueError('Invalid terrain profile angles')
        return profile
    except (KeyError, TypeError, json.JSONDecodeError): raise ValueError('Terrain profile is damaged') from None


def estimate(place, state, allowed=False, tile_loader=download_tile):
    if type(allowed) is not bool: raise ValueError('Terrain download consent must be explicit')
    if not -70 <= place['lat'] <= 70: raise ValueError('This first terrain estimate supports locations between 70°S and 70°N')
    existing = load_profile(place, state)
    if existing: return existing
    height = observing_height(place.get('observingHeight',1.7))
    lat,lon = ray_points(place['lat'],place['lon'])
    lat = np.append(lat.ravel(),place['lat']);lon = np.append(lon.ravel(),place['lon'])
    south,west = np.floor(lat).astype(int),np.floor(lon).astype(int)
    tiles = sorted(set(zip(south.tolist(),west.tolist())))
    if len(tiles)>16: raise ValueError('This location requires too many terrain tiles')
    elevations = np.empty_like(lat); deadline = time.monotonic()+180
    for y,x in tiles:
        grid = tile_loader(y,x,state/'terrain/tiles',allowed,deadline)
        select = (south==y)&(west==x)
        elevations[select] = sample_grid(grid,lat[select],lon[select],y,x)
    ground = float(elevations[-1]); heights = elevations[:-1].reshape(720,-1)
    skyline = np.maximum(0,np.max(angles(heights,ground,height),axis=1))
    profile = {'key':profile_key(place),'model':MODEL,'source':SOURCE,'sourceUrl':SOURCE_URL,
        'creditsUrl':CREDITS_URL,'created':datetime.now(timezone.utc).isoformat(),
        'observingHeight':height,'groundElevation':ground,'rangeKm':50,'gridArcSeconds':1,
        'bearingStep':.5,'radialStepM':100,'samples':np.round(skyline,3).tolist(),
        'tiles':[tile_id(y,x) for y,x in tiles],
        'limits':'Estimated terrain only: 100 m–50 km range, 0.5° bearings, 100 m radial sampling; nominal 1 arc-second grid (~31 m north/south), source accuracy/age vary. No trees/buildings, atmospheric refraction or guarantees of a clear view. Mountains beyond 50 km and narrow ridges may be missed. Download date is not survey date.'}
    path = state/'terrain/profiles'/(profile['key']+'.json');path.parent.mkdir(mode=0o700,parents=True,exist_ok=True)
    temp = path.with_suffix('.tmp');temp.write_text(json.dumps(profile));temp.chmod(0o600);temp.replace(path)
    return profile


def combined_altitude(bearings, manual, terrain):
    from observatory.trips.horizon import altitude
    base = altitude(bearings,manual)
    if not terrain: return base
    return np.maximum(base,np.interp(np.asarray(bearings)%360,np.arange(721)/2,terrain['samples']+[terrain['samples'][0]]))
