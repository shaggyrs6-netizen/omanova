const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs');
function load(path){const c={};vm.createContext(c);vm.runInContext(fs.readFileSync(path,'utf8').replace(/^\.pragma library\n/,''),c);return c;}
const nav=load('qml/Omanova/Navigation.js'),night=load('qml/Omanova/Tonight.js');
test('All 29 pages have stable, unique keys and preserve event/IPC adapters',()=>{
 assert.equal(nav.pages.length,29);assert.equal(new Set(nav.pages.map(p=>p.id)).size,29);assert.equal(new Set(nav.pages.map(p=>p.legacy)).size,29);
 for(const p of nav.pages){assert.equal(nav.fromLegacy(p.legacy),p.id);assert.ok(nav.groups.some(g=>g.id===p.group));assert.ok(nav.sectionPages(p.group,true).some(v=>v.id===p.id));}
 assert.equal(nav.fromLegacy(99),'');assert.equal(nav.available(false).length,16);
});
test('Tonight selects best first, then time order; never widens stale/equipment/interest eligibility',()=>{
 const now=Date.parse('2026-11-15T18:00Z');const row=(id,hour,score)=>({id,start:new Date(now+hour*3600000).toISOString(),end:new Date(now+(hour+1)*3600000).toISOString(),score,kind:'station',recommended:true,visibility:'possible'});
 const rows=[row('soon',1,5),row('best',4,30),row('middle',2,10),{...row('stale',0,100),visibility:'stale'}, {...row('poor',0,99),recommended:false},row('equipment',1,101),row('ended',-2,500),row('after-night',20,100)];
 const select=stale=>night.select(rows,now,stale,['station'],r=>r.id!=='equipment',now+12*3600000);
 assert.deepEqual(Array.from(select(false),r=>r.id),['best','soon','middle']);assert.equal(select(true).length,0);
 assert.equal(night.select(rows,now,false,[],()=>true,now+86400000).length,0);
});
test('Runtime status distinguishes absent, stale and future-clock data; identity checks builds',()=>{
 const now=Date.now();const data=age=>({generated:new Date(now-age).toISOString()});
 assert.match(night.runtimeStatus(null,now,false),/Waiting/);assert.equal(night.runtimeStatus(data(60000),now,false),'Snapshot current');assert.match(night.runtimeStatus(data(181000),now,false),/stale/);assert.match(night.runtimeStatus(data(-1000),now,false),/clock/);assert.match(night.runtimeStatus({generated:'invalid'},now,false),/invalid/);
 assert.equal(night.sameBuild(null,{}),null);assert.equal(night.sameBuild({version:'1',build:'a'},{version:'1',build:'b'}),false);assert.equal(night.sameBuild({version:'1',build:'a',revision:'a'},{version:'1',build:'a',revision:'b'}),false);
});
test('Tonight summary respects stale weather and offers only aligned dark low-cloud context',()=>{
 const now=Date.parse('2026-11-27T20:00Z');
 const start=new Date(now+3600000).toISOString(),end=new Date(now+7200000).toISOString();
 const pick={name:'Sample ISS',start,end,conditions:{label:'Favourable',dewRisk:'High'},look:{direction:'NW',el:43}};
 const result=night.brief([pick],null,now,false,true);
 assert.equal(result.status,'Worth a look');
 assert.equal(result.dew,'High');
 assert.equal(night.brief([pick],null,now,false,false).summary,'Sample ISS · Forecast uncertain');
 assert.equal(night.brief([pick],null,now,true,true).start,undefined);
 const hour={time:start,light:'dark',moonUp:false,cloud:15,dewRisk:'Low'};
 assert.equal(night.brief([],{hours:[hour]},now,false,true).status,'A dark, low-cloud hour');
 assert.equal(night.brief([],{hours:[{...hour,moonUp:true}]},now,false,true).start,undefined);
 assert.equal(night.brief([],{hours:[{...hour,cloud:null}]},now,false,true).start,undefined);
});
