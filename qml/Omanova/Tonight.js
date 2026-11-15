.pragma library
function select(rows, now, stale, interests, match, end) {
    if(stale || !Number.isFinite(now)) return [];
    const eligible = rows.filter(r => r.recommended && r.visibility === "possible" &&
        Number.isFinite(Date.parse(r.end)) && Date.parse(r.end)>now &&
        Date.parse(r.start)<end && interests.includes(r.kind) && match(r));
    eligible.sort((a,b) => b.score-a.score || Date.parse(a.start)-Date.parse(b.start));
    if(!eligible.length) return [];
    const first=eligible.shift();
    eligible.sort((a,b) => Date.parse(a.start)-Date.parse(b.start) || b.score-a.score);
    return [first].concat(eligible).slice(0,5);
}
function runtimeStatus(data, now, fixture) {
    if(fixture) return "Sample data";
    if(!data) return "Waiting for worker data";
    const age=now-Date.parse(data.generated);
    if(!Number.isFinite(age)) return "Snapshot time invalid";
    if(age<0) return "Snapshot clock mismatch";
    if(age>180000) return "Snapshot stale · check worker";
    return "Snapshot current";
}
function sameBuild(a,b) {
    if(!a || !b) return null;
    return a.version===b.version && a.build===b.build &&
        (!a.revision || !b.revision || a.revision===b.revision);
}
