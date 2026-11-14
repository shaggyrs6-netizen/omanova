// Test the actual pure JS used by QML, without a desktop or extra dependency.
const fs=require('fs'),vm=require('vm'),assert=require('assert/strict'),path=require('path');
const code=fs.readFileSync(path.join(__dirname,'../qml/Omanova/Colors.js'),'utf8').replace(/^\.pragma library\n/,'');
const c={};vm.createContext(c);vm.runInContext(code,c);
assert.equal(c.palette('background="red"\nforeground="#ffffff"'),null);
assert.equal(c.palette('background="#101010"'),null);
assert.equal(c.parse('accent="#123456" # comment\nforeground = "#abcdef"').foreground,'#abcdef');
assert.equal(c.parse('accent=";console.log(1)"').accent,undefined);
for(const bg of ['#ffffff','#f5f2e9','#19151e','#000000','#777777','#888888','#eeeeee']) {
 const p=c.palette(`background="${bg}"\nforeground="#777777"\naccent="${bg}"\nmuted="${bg}"\ngreen="${bg}"\nyellow="${bg}"\nred="${bg}"`);
 for(const k of ['ink','muted','accent','good','warning','bad','violet','terrain']) {
  for(const surface of ['background','surface','button','field','hover'])assert.ok(c.contrast(p[k],p[surface])>=4.49,`${bg} ${k} ${surface}`);
 }
 for(const surface of ['background','surface','button','field','hover'])assert.ok(c.contrast(p.border,p[surface])>=2.99);
}
console.log('Theme parser, invalid input, light/dark/mid-grey contrast and status roles passed');
for(const mode of ['dim','red']){
 const p=c.observing(mode);
 for(const role of ['ink','muted','accent','good','warning','bad','violet','terrain'])for(const bg of ['background','surface','field','button','hover'])assert.ok(c.contrast(p[role],p[bg])>=4.49,`${mode} ${role} ${bg}`);
 for(const bg of ['background','surface','field','button','hover'])assert.ok(c.contrast(p.border,p[bg])>=2.99,`${mode} border ${bg}`);
}
assert.equal(c.observing('normal'),null);
