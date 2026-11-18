const {readFileSync} = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const {test} = require('node:test');

const projection = vm.createContext({});
vm.runInContext(readFileSync('observatory/final_sky/CameraProjection.js','utf8').replace(/^\.pragma library\n/,''), projection);

const frame = {widthDeg: 4, heightDeg: 2};
const close = (actual, expected) => assert.ok(Math.abs(actual - expected) < 1e-9);

test('position angle swaps what fits along the long sensor axis', () => {
    const centre = {az: 0, el: 90};
    const east = {az: 90, el: 88.5};
    const north = {az: 0, el: 88.5};
    const angle = Math.tan(1.5 * Math.PI / 180);
    const half = projection.halfFrame(frame);
    const zero = projection.basis(centre, 36, 0);
    const quarter = projection.basis(centre, 36, 90);
    close(projection.project(east, zero).x, -angle);
    close(projection.project(north, zero).y, angle);
    close(projection.project(east, quarter).y, angle);
    close(projection.project(north, quarter).x, angle);
    assert.ok(angle < half.x && angle > half.y);
});

test('three-dimensional frame edges round-trip near the north bearing and horizon', () => {
    const axes = projection.basis({az: 359, el: 1}, 36, 37);
    const half = projection.halfFrame(frame);
    const outline = projection.footprint(frame, axes);
    assert.equal(outline.length, 64);
    assert.ok(outline.some(point => point.el < 0));
    assert.ok(outline.some(point => point.az < 2));
    for (const point of outline) {
        const p = projection.project(point, axes);
        close(Math.max(Math.abs(p.x)/half.x, Math.abs(p.y)/half.y), 1);
    }
});

test('camera pole fallback and whole-chart click projection stay finite', () => {
    const axes = projection.basis({az: 0, el: 36}, 36, 0);
    assert.equal(axes.atPole, true);
    const point = projection.project({az: 0, el: 36}, axes);
    close(point.x, 0);
    close(point.y, 0);
    assert.equal(projection.chartDirection(0, 60, 50), null);
    const sky = projection.chartDirection(-25, 0, 50);
    close(sky.az, 90);
    close(sky.el, 45);
    assert.equal(projection.project({az: 180, el: -36}, axes), null);
});
