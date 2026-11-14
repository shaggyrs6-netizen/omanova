.pragma library
function evaluate(row,p){
 p=p||{gear:['eye'],sky:'unknown',filter:true,uncertain:true};if(p.filter===false)return true;
 const k=row.kind,n=row.name||'',gear=p.gear||[];let options=null,dark=false;
 if(k==='moon'||k==='planet'&&['Mercury','Venus','Mars','Jupiter','Saturn'].includes(n)||k==='eclipse'&&/lunar/i.test(n))options=['eye','binoculars','telescope','camera'];
 else if(k==='station')options=['eye','binoculars','camera'];
 else if(['meteor','plume','train','aurora'].includes(k)){options=['eye','camera'];dark=true}
 else if(k==='conjunction')options=['eye','camera'];
 else if(k==='landmark')options=['eye','binoculars','camera'];
 else if(k==='deep-sky'){options=n.includes('M57')?['telescope']:n.includes('M13')?['binoculars','telescope']:['eye','binoculars','telescope','camera'];dark=true}
 else if(k==='comet'){const m=(row.reason||'').match(/^Equipment: (eye|binoculars|telescope|large)\./);if(m)options={eye:['eye','binoculars','telescope'],binoculars:['binoculars','telescope'],telescope:['telescope'],large:null}[m[1]];dark=true}
 if(k==='eclipse'&&(/solar/i.test(n)||row.safety))return false;
 if(!gear.length||options&&!gear.some(g=>options.includes(g))||dark&&['bright','moderate'].includes(p.sky))return false;
 const uncertain=!row.look||!Number.isFinite(row.look.az)||!Number.isFinite(row.look.el)||row.look.el<=0||!options||dark&&(!p.sky||p.sky==='unknown')||row.visibility!=='possible'||!['Favourable','Mixed','Poor'].includes(row.conditions?.label)||!row.conditions?.fetched||['plume','train','aurora'].includes(k);
 return p.uncertain!==false||!uncertain;
}
function validProfile(p){
 if(!p||!Array.isArray(p.gear)||p.gear.length>4||p.gear.some(g=>!['eye','binoculars','telescope','camera'].includes(g))||!['unknown','bright','moderate','dark'].includes(p.sky))return false;
 for(const k of ['filter','uncertain','showExcluded'])if(typeof p[k]!=='boolean')return false;
 for(const [k,lo,hi] of [['apertureMm',20,600],['fieldOfViewDeg',.1,180],['binocularMagnification',2,30]])if(p[k]!==undefined&&p[k]!==null&&(typeof p[k]!=='number'||!Number.isFinite(p[k])||p[k]<lo||p[k]>hi))return false;
 return p.cameraMode===undefined||['unknown','widefield','tracked'].includes(p.cameraMode);
}
