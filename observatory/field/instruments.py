"""Explicit local tools for Sky Finder. Nothing runs on page load."""
import json
import math
from contextlib import closing
from datetime import UTC, datetime
from pathlib import Path
import re
import shutil
import subprocess
import sys
from tempfile import TemporaryDirectory

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from observatory.field.field import CAT, ROOT, point
from observatory.trips.terrain import combined_altitude
from observatory.field.stellarium import focus


def tool(name, arguments, timeout=8, input_text=None):
    binary = shutil.which(name)
    if not binary:
        raise ValueError(f'{name} is unavailable. See the Sky Finder instrument setup in the README.')
    try:
        result = subprocess.run([binary, *arguments], capture_output=True, text=True,
                                timeout=timeout, check=True, input=input_text)
    except subprocess.TimeoutExpired:
        raise ValueError(f'{name} timed out.') from None
    except (OSError, subprocess.CalledProcessError):
        raise ValueError(f'{name} could not complete the request. Check its setup and inputs.') from None
    return result.stdout


def local_file(value, suffixes):
    path = Path(value).expanduser()
    if not path.is_absolute() or path.suffix.lower() not in suffixes or not path.is_file():
        raise ValueError('Enter the full path to a supported local file.')
    return path.resolve()


def estimate(request):
    atlas = local_file(request['path'], {'.tif', '.tiff'})
    metadata = json.loads(tool('gdalinfo', ['-json', '-nomd', '-norat', '-noct', str(atlas)]))
    bands = metadata.get('bands', [])
    if metadata.get('driverShortName') != 'GTiff' or len(bands) != 1:
        raise ValueError('Choose the single-band World Atlas GeoTIFF.')
    site, _ = point(request['source'], load_terrain=False)
    output = tool('gdallocationinfo', ['-valonly', '-wgs84', '-b', '1', str(atlas)], input_text=f"{site['lon']} {site['lat']}\n")
    try:
        value = float(output.strip())
    except ValueError:
        raise ValueError('The atlas has no estimate for this location.') from None
    if not math.isfinite(value) or value == bands[0].get('noDataValue') or not 0 <= value <= 1000:
        raise ValueError('The atlas has no estimate for this location.')
    return {'message': f'Estimated artificial skyglow at zenith: {value:.3g} mcd/m². '
                       'World Atlas 2015 model. Local lights, weather and Moon are separate.'}


def solve(request):
    image = local_file(request['path'], {'.fit', '.fits', '.fts', '.jpg', '.jpeg', '.png'})
    with TemporaryDirectory(prefix='omanova-solve-') as directory:
        # Copy to a controlled name so the solver cannot write beside the original.
        sample = Path(directory)/('input' + image.suffix)
        if image.stat().st_size > 100 * 1024 * 1024:
            raise ValueError('Choose a local image up to 100 MiB.')
        shutil.copyfile(image, sample)
        wcs = Path(directory)/'result.wcs'
        tool('solve-field', ['--no-plots', '--dir', directory, '--cpulimit', '60',
                             '--wcs', str(wcs), str(sample)], timeout=75)
        if not wcs.is_file():
            raise ValueError('No plate solution. Check the image and install index files for its field size.')
        values = dict(line.split(maxsplit=1) for line in tool('wcsinfo', [str(wcs)]).splitlines()
                      if len(line.split(maxsplit=1)) == 2)
        ra, dec, scale, rotation = (float(values[key]) for key in
                                    ('ra_center', 'dec_center', 'pixscale', 'orientation'))
        if not (all(map(math.isfinite, (ra, dec, scale, rotation))) and
                0 <= ra < 360 and -90 <= dec <= 90 and scale > 0):
            raise ValueError('The plate solution has invalid coordinates or scale.')
    return {'message': f'Plate solved · centre RA {ra/15:.5f} h · Dec {dec:+.5f}° · '
                       f'{scale:.3f} arcsec/pixel · rotation {rotation:+.2f}°'}


def pointing(target):
    from skyfield.api import Star, load, load_file, wgs84

    site, terrain = point('active')
    time = load.timescale(builtin=True).from_datetime(datetime.now(UTC))
    with closing(load_file(str(ROOT/'assets/de440s.bsp'))) as eph:
        observer = eph['earth'] + wgs84.latlon(site['lat'], site['lon'], site['elevation'])
        here = observer.at(time)
        if here.observe(eph['sun']).apparent().altaz()[0].degrees > -18:
            raise ValueError('Go To is available during astronomical darkness.')
        apparent = here.observe(Star(ra_hours=target['ra'], dec_degrees=target['dec'])).apparent()
        altitude, azimuth, _ = apparent.altaz()
        if altitude.degrees < 20 or altitude.degrees <= combined_altitude(azimuth.degrees, site['horizon'], terrain):
            raise ValueError('Target is below 20° or blocked by the saved horizon.')
        ra, dec, _ = apparent.radec(epoch='date')
        return ra.hours % 24, dec.degrees


def mount(action, request):
    device = request['device'].strip()
    if not re.fullmatch(r"[\w ()+/',:-]{1,80}", device):
        raise ValueError('Enter the exact INDI telescope device name.')
    base = ['-h', '127.0.0.1', '-p', '7624', '-t', '3']

    def get(prop):
        key = f'{device}.{prop}'
        for line in tool('indi_getprop', [*base, key]).splitlines():
            label, _, value = line.partition('=')
            if label == key:
                return value
        raise ValueError('The INDI server did not return the expected telescope property.')

    def set_prop(prop, value):
        tool('indi_setprop', [*base, f'{device}.{prop}={value}'])

    if action == 'stop':
        set_prop('TELESCOPE_ABORT_MOTION.ABORT', 'On')
        return {'message': 'Stop request sent. Check that the mount has stopped.'}
    if get('CONNECTION.CONNECT') != 'On':
        raise ValueError('Connect and align the telescope in your INDI controller first.')
    if action == 'position':
        ra = float(get('EQUATORIAL_EOD_COORD.RA'))
        dec = float(get('EQUATORIAL_EOD_COORD.DEC'))
        if not 0 <= ra <= 24 or not -90 <= dec <= 90:
            raise ValueError('The mount did not report valid coordinates.')
        return {'message': f'Mount position of date · RA {ra:.5f} h · Dec {dec:+.5f}°'}
    if request.get('confirm') is not True:
        raise ValueError('Confirm the telescope is aligned, clear to move and under supervision.')
    target = next((item for item in CAT['targets'] if item['id'] == request['target']), None)
    if target is None:
        raise ValueError('Select a deep-sky catalogue target first.')
    ra, dec = pointing(target)
    set_prop('ON_COORD_SET.TRACK', 'On')
    set_prop('EQUATORIAL_EOD_COORD.RA;DEC', f'{ra:.9f};{dec:.9f}')
    return {'message': f'Go To requested for {target["name"]}. Check movement in your INDI controller.'}


def main():
    try:
        data = sys.stdin.buffer.readline(8193)
        if len(data) > 8192 or not data.endswith(b'\n'):
            raise ValueError('Invalid instrument request.')
        request = json.loads(data)
        action = request['action']
        if action == 'skyglow':
            result = estimate(request)
        elif action == 'stellarium':
            result = {'message': focus(request['target'])}
        elif action == 'solve':
            result = solve(request)
        elif action in ('position', 'goto', 'stop'):
            result = mount(action, request)
        else:
            raise ValueError('Unknown instrument action.')
    except json.JSONDecodeError:
        result = {'message': 'The instrument returned an unreadable result.'}
    except ValueError as error:
        result = {'message': str(error)}
    except (OSError, KeyError, TypeError):
        result = {'message': 'The instrument result is unavailable. Check its inputs and setup.'}
    print(json.dumps(result))


if __name__ == '__main__':
    main()
