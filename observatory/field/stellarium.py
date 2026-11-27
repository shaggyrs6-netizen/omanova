"""Send only an explicit, selected Messier target to local Stellarium."""
import http.client
import re
from urllib.parse import urlencode


def focus(target, connect=http.client.HTTPConnection):
    if not isinstance(target, str) or not re.fullmatch(r'M[1-9][0-9]{0,2}', target):
        raise ValueError('Select a Messier target.')
    connection = connect('127.0.0.1', 8090, timeout=3)
    try:
        request = urlencode({'target': target, 'mode': 'center'})
        connection.request('POST', '/api/main/focus', request,
                           {'Content-Type': 'application/x-www-form-urlencoded'})
        response = connection.getresponse()
        result = response.read(64).strip()
        if response.status != 200:
            raise ValueError('Stellarium did not accept the request. Check its Remote Control settings.')
        if result != b'true':
            raise ValueError(f'Stellarium did not recognise {target}.')
    except (OSError, http.client.HTTPException) as error:
        raise ValueError('Start Stellarium and enable its Remote Control plugin on local port 8090.') from error
    finally:
        connection.close()
    return f'Stellarium centred on {target}.'
