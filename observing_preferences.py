"""Validated, local observing preferences shared by planning and alerts."""
from copy import deepcopy
from math import isfinite
import re

KINDS = ('station', 'satellite', 'moon', 'meteor', 'planet', 'conjunction',
         'comet', 'eclipse', 'launch', 'plume', 'train', 'aurora')
DEFAULTS = {
    'interests': list(KINDS), 'alert_types': ['station'], 'alert_lead_minutes': 15,
    'quiet_enabled': False, 'quiet_start': '22:00', 'quiet_end': '07:00',
    'alert_conditions': 'Favourable', 'minimum_elevation': 10,
    'watchlist': [{'number': n, 'name': name} for n, name in (
        (25544,'ISS'),(48274,'Tiangong'),(20580,'Hubble'),(27386,'Envisat'),
        (25994,'Terra'),(27424,'Aqua'),(39766,'ALOS-2'))],
}


def validate(values):
    if not isinstance(values, dict) or set(values)-set(DEFAULTS):
        raise ValueError('Unknown observing preference')
    result={}
    for key,value in values.items():
        if key in ('interests','alert_types'):
            if not isinstance(value,list) or len(value)>len(KINDS) or any(v not in KINDS for v in value):
                raise ValueError('Choose recognised event types')
            value=list(dict.fromkeys(value))
        elif key=='alert_lead_minutes':
            if type(value)!=int or not 1<=value<=120: raise ValueError('Lead time must be 1–120 minutes')
        elif key=='minimum_elevation':
            if type(value) not in (int,float) or not isfinite(value) or not 0<=value<=90:
                raise ValueError('Minimum elevation must be 0–90 degrees')
        elif key=='quiet_enabled':
            if type(value)!=bool: raise ValueError('Quiet hours require true or false')
        elif key in ('quiet_start','quiet_end'):
            if not isinstance(value,str) or not re.fullmatch(r'(?:[01]\d|2[0-3]):[0-5]\d',value):
                raise ValueError('Use HH:MM for quiet hours')
        elif key=='alert_conditions':
            if value not in ('Favourable','Mixed','Any'): raise ValueError('Choose an alert weather threshold')
        elif key=='watchlist':
            if not isinstance(value,list) or len(value)>20: raise ValueError('Choose up to 20 satellites')
            cleaned=[]; seen=set()
            for row in value:
                if not isinstance(row,dict) or set(row)!={'number','name'}:
                    raise ValueError('Each satellite needs a NORAD number and display name')
                number=row['number'];name=row['name']
                if type(number)!=int or not 1<=number<=999999 or not isinstance(name,str):
                    raise ValueError('Use a valid NORAD number and name')
                name=' '.join(name.split())
                if not name or len(name)>64 or number in seen: raise ValueError('Use unique satellite numbers and short names')
                seen.add(number);cleaned.append({'number':number,'name':name})
            value=cleaned
        result[key]=value
    return result


def preferences(settings):
    result=deepcopy(DEFAULTS)
    raw=settings.get('observing',{})
    if isinstance(raw,dict):
        for key,value in raw.items():
            try: result.update(validate({key:value}))
            except (ValueError,TypeError): pass
    return result


def in_quiet_hours(now, settings):
    prefs=preferences(settings)
    if not prefs['quiet_enabled']: return False
    clock=now.astimezone().strftime('%H:%M')
    start,end=prefs['quiet_start'],prefs['quiet_end']
    if start==end:return True
    return start<=clock<end if start<end else clock>=start or clock<end
