.pragma library

function compare(field, extent) {
    const hasField = typeof field === "number" && Number.isFinite(field) && field >= 0.1 && field <= 180
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
