const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs'),{execFileSync}=require('node:child_process');
const c={};vm.createContext(c);vm.runInContext(fs.readFileSync('qml/Omanova/Equipment.js','utf8').replace(/^\.pragma library\n/,''),c);
const cases=JSON.parse(execFileSync(process.env.PYTHON||'.venv/bin/python',['-c',`
from observatory.equipment.equipment import profile,fixtures,assess
from datetime import datetime,UTC
from astronomy import iso
import json
now=datetime(2026,11,14,18,tzinfo=UTC);cases=[]
for gear in ([],['eye'],['binoculars'],['telescope'],['camera'],['eye','telescope']):
 for sky in ('unknown','bright','moderate','dark'):
  for uncertain in (True,False):
   p=profile({'gear':gear,'sky':sky,'uncertain':uncertain})
   for r in fixtures(now):
    if r.get('sampleRule'):continue
    a=assess(r,p,now,iso(now));cases.append({'row':r,'profile':p,'match':not a['excluded']})
print(json.dumps(cases))
`],{encoding:'utf8',env:{...process.env,OPENBLAS_NUM_THREADS:'1'}}));
test('Overview equipment rules agree with export/backend rules',()=>{for(const x of cases)assert.equal(c.evaluate(x.row,x.profile),x.match,JSON.stringify([x.row.name,x.profile]));});
test('Invalid equipment profile is rejected rather than widening suggestions',()=>{assert.equal(c.validProfile({gear:['laser'],sky:'dark',filter:true,uncertain:true,showExcluded:false}),false);assert.equal(c.validProfile({gear:['eye'],sky:'dark',filter:true,uncertain:true,showExcluded:false,apertureMm:NaN}),false)});
