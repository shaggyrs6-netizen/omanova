.pragma library

const radians = Math.PI / 180

function direction(az, el) {
    const a = az * radians, h = el * radians
    return [Math.cos(h) * Math.sin(a), Math.cos(h) * Math.cos(a), Math.sin(h)]
}

function dot(a, b) {
    return a[0]*b[0] + a[1]*b[1] + a[2]*b[2]
}

function cross(a, b) {
    return [a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0]]
}

function combine(a, b, x, y) {
    return a.map((v, i) => x*v + y*b[i])
}

function unit(v) {
    const length = Math.hypot(v[0], v[1], v[2])
    return v.map(value => value / length)
}

function basis(centre, poleAltitude, rotation) {
    const forward = direction(centre.az, centre.el)
    const pole = direction(0, poleAltitude)
    let east = cross(pole, forward)
    const atPole = Math.hypot(east[0], east[1], east[2]) < 1e-7
    if (atPole) east = direction(centre.az + 90, 0)
    const west = unit(east).map(value => -value)
    const north = unit(cross(west, forward))
    const angle = rotation * radians
    return {
        forward,
        right: combine(west, north, Math.cos(angle), Math.sin(angle)),
        up: combine(north, west, Math.cos(angle), -Math.sin(angle)),
        atPole
    }
}

function planeVector(v, axes) {
    const depth = dot(v, axes.forward)
    if (depth < 1e-6) return null
    return {x: dot(v, axes.right) / depth, y: dot(v, axes.up) / depth}
}

function project(row, axes) {
    return planeVector(direction(row.az, row.el), axes)
}

function halfFrame(camera) {
    return {x: Math.tan(camera.widthDeg*radians/2), y: Math.tan(camera.heightDeg*radians/2)}
}

function planeDirection(x, y, axes) {
    const offset = combine(axes.right, axes.up, x, y)
    return axes.forward.map((value, i) => value + offset[i])
}

function horizontal(v) {
    return {az: (Math.atan2(v[0], v[1])/radians + 360) % 360,
            el: Math.atan2(v[2], Math.hypot(v[0], v[1]))/radians}
}

function footprint(camera, axes) {
    const half = halfFrame(camera)
    const corners = [[-half.x,-half.y], [half.x,-half.y], [half.x,half.y], [-half.x,half.y]]
    const points = []
    // Sample sensor edges before mapping to the whole-sky chart's radial projection.
    for (let side = 0; side < 4; side++) {
        const a = corners[side], b = corners[(side+1)%4]
        for (let i = 0; i < 16; i++) {
            const f = i/16
            points.push(horizontal(planeDirection(a[0]+(b[0]-a[0])*f, a[1]+(b[1]-a[1])*f, axes)))
        }
    }
    return points
}

function targetOutline(row, axes) {
    const targetAxes = basis(row, 90, 0)
    const radius = Math.tan(row.extent*radians/2)
    const points = []
    for (let i = 0; i <= 32; i++) {
        const angle = i*Math.PI/16
        points.push(planeVector(planeDirection(radius*Math.cos(angle), radius*Math.sin(angle), targetAxes), axes))
    }
    return points
}

function chartDirection(x, y, radius) {
    if (radius <= 0 || Math.hypot(x,y) > radius) return null
    return {az: (Math.atan2(-x,-y)/radians+360)%360, el: 90*(1-Math.hypot(x,y)/radius)}
}
