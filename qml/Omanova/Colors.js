.pragma library
function parse(text) {
    const out={}
    for (const line of String(text).slice(0,65536).split(/\r?\n/)) {
        const match=line.match(/^\s*([a-zA-Z_][a-zA-Z_0-9]*)\s*=\s*["'](#[0-9a-fA-F]{6})["']\s*(?:#.*)?$/)
        if(match)out[match[1]]=match[2]
    }
    return out
}
function rgb(hex) {return [1,3,5].map(i=>parseInt(hex.slice(i,i+2),16)/255)}
function hex(values) {return '#'+values.map(v=>Math.round(Math.max(0,Math.min(1,v))*255).toString(16).padStart(2,'0')).join('')}
function blend(a,b,t) {const x=rgb(a),y=rgb(b);return hex(x.map((v,i)=>v*(1-t)+y[i]*t))}
function luminance(c) {const x=rgb(c).map(v=>v<=.04045?v/12.92:Math.pow((v+.055)/1.055,2.4));return x[0]*.2126+x[1]*.7152+x[2]*.0722}
function contrast(a,b) {const x=luminance(a),y=luminance(b);return (Math.max(x,y)+.05)/(Math.min(x,y)+.05)}
function readable(color,bg,ratio) {
    if(contrast(color,bg)>=ratio)return color
    const target=contrast('#ffffff',bg)>contrast('#000000',bg)?'#ffffff':'#000000'
    for(let i=1;i<=20;i++){const next=blend(color,target,i/20);if(contrast(next,bg)>=ratio)return next}
    return target
}
function palette(text) {
    const p=parse(text)
    if(!p.background||!p.foreground)return null
    const bg=p.background,fg=readable(p.foreground,bg,7)
    function safe(t) {const c=blend(bg,fg,t);return contrast(fg,c)>=4.5?c:bg}
    const surface=safe(.055),field=safe(.035),button=safe(.10),hover=safe(.14)
    function onAll(color,ratio) {
        const target=contrast('#ffffff',bg)>contrast('#000000',bg)?'#ffffff':'#000000'
        for(let i=0;i<=20;i++) {
            const c=blend(color,target,i/20)
            if([bg,surface,field,button,hover].every(b=>contrast(c,b)>=ratio))return c
        }
        return fg
    }
    return {background:bg,surface:surface,field:field,button:button,hover:hover,ink:onAll(fg,4.5),
        muted:onAll(p.muted||fg,4.5),accent:onAll(p.accent||p.blue||fg,4.5),
        violet:onAll(p.magenta||p.accent||fg,4.5),border:onAll(blend(bg,fg,.40),3),
        good:onAll(p.green||'#21874b',4.5),warning:onAll(p.yellow||'#ae6d00',4.5),
        bad:onAll(p.red||'#bd3041',4.5),terrain:onAll(p.orange||'#b66d21',4.5)}
}

function observing(mode) {
 if(mode==='dim')return palette('background="#03080b"\nforeground="#a8c0c3"\naccent="#98bbbd"\nmuted="#94afb1"')
 if(mode==='red')return {background:'#0c0202',surface:'#180605',field:'#120403',button:'#240807',hover:'#300b09',ink:'#ffaaa0',muted:'#f28f86',accent:'#ffc0b8',violet:'#ffaaa0',border:'#ce6c64',good:'#ffc0b8',warning:'#ffaaa0',bad:'#ffd0c8',terrain:'#ffaaa0'}
 return null
}
