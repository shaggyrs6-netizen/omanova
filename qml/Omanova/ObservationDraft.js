.pragma library
function localStamp(date) {
    const pad=n=>String(n).padStart(2,"0");
    const offset=-date.getTimezoneOffset(), absolute=Math.abs(offset);
    return date.getFullYear()+"-"+pad(date.getMonth()+1)+"-"+pad(date.getDate())+"T"+
        pad(date.getHours())+":"+pad(date.getMinutes())+(offset<0?"-":"+")+
        pad(Math.floor(absolute/60))+":"+pad(absolute%60);
}
function make(event, place, now, token) {
    if(!event || typeof event.name!=="string" || !event.name.trim() || !Number.isFinite(now.getTime())) return null;
    return {token:token,seen:event.name.trim().slice(0,120),place:typeof place==="string"?place.slice(0,120):"",
        observed:localStamp(now),notes:"",
        context:"Selected event: "+event.name.slice(0,120)+(event.assessment?" · "+String(event.assessment).slice(0,200):"")+". Observation time defaults to now; check it before saving."};
}
