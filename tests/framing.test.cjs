const {readFileSync} = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const {test} = require('node:test');

const context = vm.createContext({});
vm.runInContext(readFileSync('qml/Omanova/Framing.js','utf8').replace(/^\.pragma library\n/,''), context);

test('saved field and catalogue width share a linear scale', () => {
    const fit = context.compare(6, 2);
    assert.equal(fit.status, 'fits');
    assert.equal(fit.fieldFraction, 1);
    assert.equal(fit.targetFraction, 1/3);
    const wide = context.compare(1, 3);
    assert.equal(wide.status, 'wide');
    assert.equal(wide.fieldFraction, 1/3);
    assert.equal(wide.targetFraction, 1);
});

test('near equal approximate widths are called a tight fit', () => {
    for (const size of [0.95, 1, 1.05]) assert.equal(context.compare(1,size).status,'edge');
});

test('unconfigured or invalid fields and missing extents suppress the drawing', () => {
    for (const field of [null, 0, 181, '3', NaN]) assert.equal(context.compare(field,2).status,'missing-field');
    for (const extent of [undefined, 0, Infinity]) assert.equal(context.compare(3,extent).status,'missing-extent');
});

test('estimates the true field from focal lengths and apparent field', () => {
    const result = context.estimate(1200, 25, 60);
    assert.equal(result.magnification, 48);
    assert.equal(result.field, 1.25);
    assert.equal(context.estimate(3000, 4, 50).field, 50 / 750);
    assert.equal(context.compare(50 / 750, 0.05).status, 'fits');
});

test('calculator rejects missing, nonphysical and out of range values', () => {
    for (const args of [[0, 25, 60], [1200, NaN, 60], [1200, 25, 181], [120000, 1, 10], [1, 900, 90]]) {
        assert.equal(context.estimate(...args), null);
    }
    assert.equal(context.decimal(' 12,5 '), 12.5);
    assert.equal(context.decimal('0x10'), NaN);
});

test('camera sensor axes give independent angles and the shorter axis limits a centred fit', () => {
    const frame = context.cameraField(36, 24, 600);
    assert.ok(Math.abs(frame.width - 3.4367160033) < 1e-8);
    assert.ok(Math.abs(frame.height - 2.2915256764) < 1e-8);
    assert.equal(context.compareFrame(frame.width, frame.height, 3).status, 'wide');
    assert.equal(context.compareFrame(frame.width, frame.height, 2.2).status, 'edge');
    assert.equal(context.compareFrame(frame.height, frame.width, 2).status, 'fits');
    assert.equal(context.compareFrame(frame.width, frame.height, frame.height * 1.01).status, 'wide');
    assert.equal(context.cameraField(0, 24, 600), null);
    assert.equal(context.cameraField(36, 24, NaN), null);
});
