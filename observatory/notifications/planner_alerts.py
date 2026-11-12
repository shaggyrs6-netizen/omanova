"""Opt-in local-event alerts with shared freshness, weather and quiet rules."""
from datetime import timedelta
from html import escape
import subprocess
from astronomy import utc
from observing_preferences import preferences, in_quiet_hours


def eligible(row, settings, now, history, location_id):
    prefs=preferences(settings)
    if settings.get('alerts') is not True or row['kind'] not in prefs['alert_types']: return False
    if in_quiet_hours(now, settings) or row['visibility']!='possible':return False
    start,end=utc(row['start']),utc(row['end'])
    if not now<start<=now+timedelta(minutes=prefs['alert_lead_minutes']):return False
    if row.get('valid_until') and now>utc(row['valid_until']):return False
    altitude=row['look'].get('el')
    if altitude is None or altitude<prefs['minimum_elevation']:return False
    label=row['conditions']['label']
    allowed={'Favourable':('Favourable',),'Mixed':('Favourable','Mixed'),
             'Any':('Favourable','Mixed','Poor','Uncertain')}[prefs['alert_conditions']]
    if label not in allowed:return False
    for sent in history:
        try:
            if (sent['location']==location_id and sent['kind']==row['kind'] and sent['object_id']==row['object_id']
                    and utc(sent['start'])<end and start<utc(sent['end'])):return False
        except (KeyError,ValueError,TypeError):continue
    return True


def record(row, location_id):
    return {key:row[key] for key in ('kind','object_id','start','end')} | {'location':location_id}


def deliver(row, minutes, *, preview=False, send=subprocess.run):
    title=('[Preview] ' if preview else '')+row['name']+' in '+str(minutes)+' minutes'
    p=row['look'];label=row['conditions']['label']
    look_time=utc(p.get('time') or row['start']).astimezone().strftime('%a %H:%M')
    body='Suggested look '+look_time+': '+str(p.get('direction') or 'at the listed bearing')
    if p.get('az') is not None:body+=' ('+str(round(p['az']))+'° true)'
    if p.get('el') is not None:body+=', '+str(round(p['el']))+'° up'
    body+='. '+('Poor visibility.' if label=='Poor' else 'Weather uncertain.' if label=='Uncertain' else 'Forecast '+label.lower()+'.')
    if row.get('safety'):body+=' '+row['safety']
    if row['kind'] in ('train','plume','aurora'):body+=' Experimental guidance; visibility is not confirmed.'
    try:
        send(['/usr/bin/notify-send','--app-name=OMANOVA','--urgency=normal','--expire-time=10000',
              '--',title,escape(body)],check=True,capture_output=True,timeout=5)
    except (OSError,subprocess.SubprocessError):return False
    return True
