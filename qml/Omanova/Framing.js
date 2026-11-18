.pragma library

function fieldIsValid(field) {
    return typeof field === "number" && Number.isFinite(field) && field >= 0.01 && field <= 180
}

function decimal(text) {
    const value = text.trim().replace(",", ".")
    return /^(?:\d+(?:\.\d*)?|\.\d+)$/.test(value) ? Number(value) : NaN
}

function estimate(telescopeMm, eyepieceMm, apparentDeg) {
    if (![telescopeMm, eyepieceMm, apparentDeg].every(value => Number.isFinite(value) && value > 0)
            || apparentDeg > 180)
        return null
    const magnification = telescopeMm / eyepieceMm
    const field = apparentDeg / magnification
    return fieldIsValid(field) ? {field, magnification} : null
}

function compare(field, extent) {
    const hasField = fieldIsValid(field)
    const hasExtent = typeof extent === "number" && Number.isFinite(extent) && extent > 0 && extent <= 180
    if (!hasField || !hasExtent)
        return {status: !hasField ? "missing-field" : "missing-extent"}
    const scale = Math.max(field, extent)
    const ratio = extent / field
    return {
        status: ratio > 1.05 ? "wide" : ratio >= 0.95 ? "edge" : "fits",
        fieldFraction: field / scale,
        targetFraction: extent / scale,
        ratio: ratio
    }
}
