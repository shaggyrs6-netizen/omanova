const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const draft={};vm.createContext(draft);vm.runInContext(fs.readFileSync('qml/Omanova/ObservationDraft.js','utf8').replace(/^\.pragma library\n/,''),draft);
test('Observation draft uses actual click time and place, never predicted geometry or automatic confirmation',()=>{
 const now=new Date('2026-11-15T12:35:17Z'),event={name:'ISS',kind:'station',start:'2026-12-01T20:00Z',assessment:'Data stale',recommended:false,look:{az:123}};
 const d=draft.make(event,'Home',now,1);
 assert.equal(d.seen,'ISS');assert.equal(d.place,'Home');assert.equal(d.notes,'');assert.equal(Date.parse(d.observed),Math.floor(now.getTime()/60000)*60000);assert.equal(d.token,1);assert.ok(d.context.includes('Data stale'));assert.equal(d.confirmed,undefined);assert.equal(d.lat,undefined);assert.equal(d.az,undefined);
});
test('Draft input is bounded, explicit and rejects invalid events/clocks',()=>{
 const d=draft.make({name:'x'.repeat(300),assessment:'z'.repeat(500)},'y'.repeat(300),new Date(),2);
 assert.equal(d.seen.length,120);assert.equal(d.place.length,120);assert.ok(d.context.length<500);
 assert.equal(draft.make(null,'Home',new Date(),1),null);assert.equal(draft.make({name:'ISS'},'Home',new Date(NaN),1),null);
});
test('Actual click time retains the correct offset during a repeated DST hour',()=>{
 const {execFileSync}=require('node:child_process');
 const code=`const fs=require('node:fs'),vm=require('node:vm'),c={};vm.createContext(c);vm.runInContext(fs.readFileSync('qml/Omanova/ObservationDraft.js','utf8').replace(/^\\.pragma library\\n/,''),c);console.log(JSON.stringify(['2026-11-01T05:30:00Z','2026-11-01T06:30:00Z'].map(t=>c.localStamp(new Date(t)))));`;
 const stamps=JSON.parse(execFileSync(process.execPath,['-e',code],{encoding:'utf8',env:{...process.env,TZ:'America/New_York'}}));
 assert.deepEqual(stamps,['2026-11-01T01:30-04:00','2026-11-01T01:30-05:00']);
});
