.pragma library

function draw(ctx, x, y, size, accent, outline) {
    ctx.save()
    ctx.translate(x, y)
    ctx.scale(size / 30, size / 30)

    // The central module and its boom connect the two pairs of solar panels.
    ctx.beginPath()
    ctx.moveTo(-12, 0)
    ctx.lineTo(12, 0)
    ctx.moveTo(0, -7)
    ctx.lineTo(0, 7)
    ctx.lineWidth = 4
    ctx.lineCap = "round"
    ctx.strokeStyle = outline
    ctx.stroke()
    ctx.lineWidth = 1.8
    ctx.strokeStyle = accent
    ctx.stroke()

    ctx.beginPath()
    ctx.rect(-14, -6, 5, 12)
    ctx.rect(-8, -6, 4, 12)
    ctx.rect(4, -6, 4, 12)
    ctx.rect(9, -6, 5, 12)
    ctx.rect(-2, -4, 4, 8)
    ctx.lineWidth = 1.8
    ctx.strokeStyle = outline
    ctx.stroke()
    ctx.fillStyle = accent
    ctx.fill()

    ctx.restore()
}
