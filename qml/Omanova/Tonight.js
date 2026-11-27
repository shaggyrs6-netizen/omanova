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

function brief(picks, strip, now, stale, weatherCurrent) {
    if (stale) return {status: "Stale data · check the worker before planning", summary: "", window: "", dew: ""};
    if (picks.length) {
        const best = picks[0];
        const label = best.conditions?.label;
        const weather = weatherCurrent && ["Favourable", "Mixed"].includes(label)
            ? label + " forecast" : "Forecast uncertain";
        return {
            status: weather === "Favourable forecast" ? "Worth a look" : "Potential viewing",
            summary: best.name + " · " + weather,
            window: new Date(best.start).getTime() <= now ? "Ongoing until" : "Suggested window",
            start: best.start, end: best.end, safety: best.safety || "",
            direction: best.look?.direction || "", elevation: best.look?.el,
            dew: weatherCurrent ? best.conditions?.dewRisk || "" : ""
        };
    }
    const hours = strip?.hours || [];
    const clear = hours.find(hour => Date.parse(hour.time) >= now && hour.light === "dark"
        && hour.moonUp === false && weatherCurrent && Number.isFinite(hour.cloud) && hour.cloud <= 30);
    if (clear) return {status: "A dark, low-cloud hour", summary: "Moon below the horizon · no matching target suggested",
        window: "From", start: clear.time, dew: clear.dewRisk || ""};
    return {status: "No current observing pick", summary: weatherCurrent ? "Explore all events and check their conditions."
        : "Forecast unavailable · explore all events for geometry and timing.", window: "", dew: ""};
}
