const {test}=require('node:test');
const assert=require('node:assert/strict');
const vm=require('node:vm');
const {execFileSync}=require('node:child_process');
const fixture=JSON.parse(execFileSync(process.env.PYTHON||'.venv/bin/python',['-c',`
from datetime import UTC,datetime,timedelta
from pathlib import Path
import json,tempfile
from observatory.offline.offline import prepare,render_html
from astronomy import iso
with tempfile.TemporaryDirectory() as tmp:
 now=datetime(2026,11,14,18,tzinfo=UTC)
 d=prepare(Path(tmp),{'zone':'America/Chicago','night':'2026-11-14'},now)
 r=next(r for r in d['rows'] if r['name']=='ISS')
 r['segmentEnd']=iso(now+timedelta(hours=12));d['rows']=[r];d['savedAt']=iso(now)
 print(json.dumps({'html':render_html(d,now),'row':r}))
`],{encoding:'utf8',env:{...process.env,OPENBLAS_NUM_THREADS:'1'}}));
const script=fixture.html.match(/<script>([\s\S]*?)<\/script>/)[1];
const start=Date.parse(fixture.row.capturedAt);
function evaluate(offset,extra={}){
 const r=fixture.row,status={},weather={};let refresh,interval;
 const card={dataset:{captured:r.capturedAt,recheck:r.recheckAt,end:r.segmentEnd,stale:'0',issue:'0',fetched:r.conditions.fetched,weather:r.weatherExpires,...extra},querySelector:s=>s==='.status'?status:weather};
 const context={Date:{now:()=>start+offset,parse:Date.parse},Number,document:{querySelectorAll:()=>[card]},setInterval:(f,n)=>{refresh=f;interval=n}};
 vm.runInNewContext(script,context,{timeout:1000});
 return {status:status.textContent,weather:weather.textContent,interval,refresh};
}
test('HTML recomputes timing and weather age without live sources',()=>{
 assert.match(evaluate(0).status,/not a live prediction/);
 assert.match(evaluate(2*3600000).status,/aged/);
 assert.match(evaluate(6*3600000).weather,/stale/);
 assert.match(evaluate(13*3600000).status,/Ended/);
 assert.equal(evaluate(0).interval,30000);
});
test('HTML preserves stale, incomplete and unknown states',()=>{
 assert.match(evaluate(0,{stale:'1'}).status,/Stale when captured/);
 assert.match(evaluate(0,{issue:'1'}).status,/Incomplete/);
 assert.match(evaluate(-1000).status,/Clock mismatch/);
 assert.match(evaluate(0,{recheck:'bad'}).status,/unknown/);
 assert.match(evaluate(0,{fetched:'',weather:''}).weather,/unknown/);
});
