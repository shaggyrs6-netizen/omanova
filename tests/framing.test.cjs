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
