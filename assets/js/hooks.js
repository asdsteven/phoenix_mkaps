const Hooks = {}

const draggings = new Set()
let ticker = 1

const getSize = (el) => {
  if (el.matches('.mkaps-sentence')) return parseInt(el.style.fontSize, 10)
  if (el.matches('.mkaps-image')) return parseInt(el.style.width, 10)
  if (el.matches('.mkaps-avatar')) return parseInt(el.style.width, 10)
  if (el.matches('.mkaps-video')) return parseInt(el.style.width, 10)
}

const xyzSize = (el) => {
  return {
    item: el.id,
    x: parseInt(el.style.left, 10),
    y: parseInt(el.style.top, 10),
    z: parseInt(el.style.zIndex, 10),
    size: getSize(el)
  }
}

const sink = (el) => {
  let z = parseInt(el.style.zIndex, 10)
  if (z == 9999) return
  const rect = el.getBoundingClientRect()
  for (const e of document.querySelectorAll('.mkaps-drag')) {
    if (e === el) continue
    const r = e.getBoundingClientRect()
    if (rect.width < r.width || rect.height < r.height) continue
    if (rect.right < r.left + r.width / 2 || rect.left > r.left + r.width / 2) continue
    if (rect.bottom < r.top + r.height / 2 || rect.top > r.top + r.height / 2) continue
    z = Math.min(z, parseInt(e.style.zIndex, 10))
  }
  el.style.zIndex = z
  const events = [xyzSize(el)]
  for (const e of document.querySelectorAll('.mkaps-drag')) {
    if (e === el) continue
    if (parseInt(e.style.zIndex, 10) == 9999) continue
    if (parseInt(e.style.zIndex, 10) < z) continue
    e.style.zIndex = parseInt(e.style.zIndex, 10) + 1
    events.push(xyzSize(e))
  }
  return events
}

const setAllOrigins = (origins) => {
  const es = []
  for (const e of document.querySelectorAll('.mkaps-sentence')) es.push(e)
  for (const e of document.querySelectorAll('.mkaps-image')) es.push(e)
  for (const e of document.querySelectorAll('.mkaps-avatar')) es.push(e)
  for (const e of document.querySelectorAll('.mkaps-video')) es.push(e)
  for (const e of es) origins.set(e, xyzSize(e))
}

const persistent = (el) => {
  const events = []
  if (el.matches('.mkaps-toggle-sentences')) {
    events.push(...Array.from(document.querySelectorAll('.mkaps-sentence')).map(xyzSize))
  }
  if (el.matches('.mkaps-toggle-images')) {
    events.push(...Array.from(document.querySelectorAll('.mkaps-image')).map(xyzSize))
    events.push(...Array.from(document.querySelectorAll('.mkaps-avatar')).map(xyzSize))
    events.push(...Array.from(document.querySelectorAll('.mkaps-video')).map(xyzSize))
  }
  return events
}

const parseStartEnd = (s) => {
  if (!s) return [NaN, NaN]
  return s.split('-').map((t) => {
    if (!t) return NaN
    const [min, sec] = t.split(':').map(Number)
    return min * 60 + sec
  })
}

Hooks.Touchable = {
  mounted() {
    const el = this.el
    let myTicker = 1
    let timeout = null

    if (el.matches('.mkaps-video')) {
      const video = el.querySelector('video')
      const [start, end] = parseStartEnd(el.dataset.startEnd)
      if (isNaN(start)) {
        video.currentTime = 0
      } else {
        video.currentTime = start
      }
      video.addEventListener('timeupdate', () => {
        const [start, end] = parseStartEnd(el.dataset.startEnd)
        if (!isNaN(start) && video.currentTime < start) {
          video.currentTime = start
          return
        }
        if (isNaN(end)) return
        if (video.currentTime < end) return
        video.pause()
        setTimeout(() => {
          if (!video.paused) return
          const [start, end] = parseStartEnd(el.dataset.startEnd)
          if (isNaN(start)) {
            video.currentTime = 0
          } else {
            video.currentTime = start
          }
          video.play()
        }, 1000)
      })
      video.addEventListener('ended', () => {
        setTimeout(() => {
          if (!video.ended) return
          const [start, end] = parseStartEnd(el.dataset.startEnd)
          if (isNaN(start)) {
            video.currentTime = 0
          } else {
            video.currentTime = start
          }
          video.play()
        }, 1000)
      })

      const showTime = () => {
        const min = String(Math.floor(video.currentTime / 60)).padStart(2, '0')
        const sec = String(Math.floor(video.currentTime % 60)).padStart(2, '0')
        el.querySelector('div').textContent = `${min}:${sec}`
      }
      showTime()
      video.addEventListener('timeupdate', showTime)
      this.handleEvent('reset_video', () => {
        const [start, end] = parseStartEnd(el.dataset.startEnd)
        if (isNaN(start)) {
          video.currentTime = 0
        } else {
          video.currentTime = start
        }
        video.pause()
        showTime()
      })
    }

    if (el.matches('img')) {
      el.addEventListener('contextmenu', (e) => {
        e.preventDefault()
      })
    }

    // State 1: no touch:     pointers.length >= 0, all pointers are not moved
    // State 2: single touch: pointers.length == 1, pointers[0] is moved
    // State 3: multi touch:  pointers.length == 2, both pointers are moved
    const pointers = []

    el.addEventListener('pointerdown', (e) => {
      // invalidate pointers
      if (myTicker != ticker) {
        myTicker = ticker
        pointers.splice(0)
      }
      if ((el.id == 'board') !=
          (document.querySelector('#board.mkaps-toggle-sentences') != null ||
           document.querySelector('#board.mkaps-toggle-images') != null)) return
      if (pointers.length == 0 || !pointers[0].moved) {
        // is State 1
        // be State 1
        pointers.push({
          ticker: ticker,
          pointerId: e.pointerId,
          originX: e.x,
          originY: e.y,
          moved: false
        })
      } else if (pointers.length == 1 && pointers[0].moved) {
        if (!document.querySelector('#board.mkaps-toggle-zoom') &&
            !document.querySelector('#board.mkaps-toggle-rotate')) return
        if (el.id != 'board' && !el.matches('.mkaps-drag')) return
        // is State 2
        // be State 3
        pointers.push({
          ticker: ticker,
          pointerId: e.pointerId,
          originX: e.x,
          originY: e.y,
          moved: true
        })
      }
    })

    const pointerend = (e) => {
      // invalidate pointers
      if (myTicker != ticker) {
        myTicker = ticker
        pointers.splice(0)
      }
      const i = pointers.findIndex(p => p.pointerId == e.pointerId)
      if (i == -1) return
      if (!pointers[0].moved) {
        // is State 1
        // be State 1
        pointers.splice(i, 1)
        if (el.matches('.mkaps-grapheme')) {
          if (draggings.size > 0) this.pushEvent('drags', Array.from(draggings).map(xyzSize))
          this.pushEvent("toggle-highlight", {
            key: el.id
          })
        } else if (el.matches('.mkaps-image')) {
          if (draggings.size > 0) this.pushEvent('drags', Array.from(draggings).map(xyzSize))
          this.pushEvent('flip', {
            image: el.id
          })
        } else if (el.matches('.mkaps-avatar')) {
          if (draggings.size > 0) this.pushEvent('drags', Array.from(draggings).map(xyzSize))
          this.pushEvent('focus', {
            avatar: el.id
          })
        } else if (el.matches('.mkaps-video')) {
          if (draggings.size > 0) this.pushEvent('drags', Array.from(draggings).map(xyzSize))
          const video = el.querySelector('video')
          if (video.paused) {
            video.play()
          } else {
            video.pause()
          }
        }
      } else if (pointers.length == 1) {
        // is State 2
        // be State 1
        pointers.splice(i, 1)
        if (el.id == 'board') {
          const events = persistent(el)
          if (events.length > 0) this.pushEvent('drags', events)
        } else if (draggings.has(el)) {
          draggings.delete(el)
          this.pushEvent('drags', sink(el))
        }
        clearTimeout(timeout)
        timeout = null
      } else  {
        // is State 3
        if (el.id == 'board') {
          pointers.splice(i, 1)
          const p = pointers[0]
          p.originX = p.x
          p.originY = p.y
          p.origins.clear()
          setAllOrigins(p.origins)
          const events = persistent(el)
          if (events.length > 0) this.pushEvent('drags', events)
        } else {
          pointers.splice(i, 1)
          const p = pointers[0]
          p.originX = p.x
          p.originY = p.y
          p.elX = parseInt(el.style.left, 10)
          p.elY = parseInt(el.style.top, 10)
          p.elZ = parseInt(el.style.zIndex, 10)
          p.elSize = getSize(el)
          this.pushEvent('drags', [xyzSize(el)])
        }
        clearTimeout(timeout)
        timeout = null
      }
    }
    window.addEventListener('pointerup', pointerend)
    window.addEventListener('pointercancel', pointerend)

    const singleTouch = () => {
      // is State 2
      const p = pointers[0]
      if (el.id == 'board') {
        if (draggings.size > 0) {
          // invalidate all other pointers
          myTicker = ++ticker
          // persistent draggings
          this.pushEvent('drags', [].concat(...Array.from(draggings).map(sink)))
          draggings.clear()
        }
        if (el.matches('.mkaps-toggle-sentences')) {
          for (const el of document.querySelectorAll('.mkaps-sentence')) {
            el.style.left = `${p.x - (p.originX - p.origins.get(el).x)}px`
            el.style.top = `${p.y - (p.originY - p.origins.get(el).y)}px`
          }
        }
        if (el.matches('.mkaps-toggle-images')) {
          for (const el of document.querySelectorAll('.mkaps-image')) {
            el.style.left = `${p.x - (p.originX - p.origins.get(el).x)}px`
            el.style.top = `${p.y - (p.originY - p.origins.get(el).y)}px`
          }
          for (const el of document.querySelectorAll('.mkaps-avatar')) {
            el.style.left = `${p.x - (p.originX - p.origins.get(el).x)}px`
            el.style.top = `${p.y - (p.originY - p.origins.get(el).y)}px`
          }
          for (const el of document.querySelectorAll('.mkaps-video')) {
            el.style.left = `${p.x - (p.originX - p.origins.get(el).x)}px`
            el.style.top = `${p.y - (p.originY - p.origins.get(el).y)}px`
          }
        }
        if (el.matches('.mkaps-toggle-strokes')) {
        }
      } else {
        el.style.left = `${p.x - (p.originX - p.elX)}px`
        el.style.top = `${p.y - (p.originY - p.elY)}px`
        if (!draggings.has(el)) {
          draggings.add(el)
          const allZ = Array.from(document.querySelectorAll('.mkaps-drag'))
                            .filter(e => e !== el && parseInt(e.style.zIndex, 10) < 9999)
                            .map(e => parseInt(e.style.zIndex, 10))
          el.style.zIndex = Math.max(0, ...allZ) + 1
        }
      }
    }

    const multiTouch = () => {
      // is State 3
      const p = pointers[0]
      const q = pointers[1]
      if (el.id == 'board') {
        const len0 = Math.sqrt(Math.pow(p.originX - q.originX, 2) + Math.pow(p.originY - q.originY, 2))
        const len1 = Math.sqrt(Math.pow(p.x - q.x, 2) + Math.pow(p.y - q.y, 2))
        const r = Math.max(0.5, Math.min(2, len1 / len0))
        if (el.matches('.mkaps-toggle-sentences')) {
          for (const e of document.querySelectorAll('.mkaps-sentence')) {
            e.style.left = `${p.x - Math.round((p.originX - p.origins.get(e).x) * r)}px`
            e.style.top = `${p.y - Math.round((p.originY - p.origins.get(e).y) * r)}px`
            e.style.fontSize = `${Math.round(p.origins.get(e).size * r)}px`
          }
        }
        if (el.matches('.mkaps-toggle-images')) {
          for (const e of document.querySelectorAll('.mkaps-image')) {
            e.style.left = `${p.x - Math.round((p.originX - p.origins.get(e).x) * r)}px`
            e.style.top = `${p.y - Math.round((p.originY - p.origins.get(e).y) * r)}px`
            e.style.width = `${Math.round(p.origins.get(e).size * r)}px`
          }
          for (const e of document.querySelectorAll('.mkaps-avatar')) {
            e.style.left = `${p.x - Math.round((p.originX - p.origins.get(e).x) * r)}px`
            e.style.top = `${p.y - Math.round((p.originY - p.origins.get(e).y) * r)}px`
            e.style.width = `${Math.round(p.origins.get(e).size * r)}px`
          }
          for (const e of document.querySelectorAll('.mkaps-video')) {
            e.style.left = `${p.x - Math.round((p.originX - p.origins.get(e).x) * r)}px`
            e.style.top = `${p.y - Math.round((p.originY - p.origins.get(e).y) * r)}px`
            e.style.width = `${Math.round(p.origins.get(e).size * r)}px`
          }
        }
        if (el.matches('.mkaps-toggle-strokes')) {
        }
      } else {
        const len0 = Math.sqrt(Math.pow(p.originX - q.originX, 2) + Math.pow(p.originY - q.originY, 2))
        const len1 = Math.sqrt(Math.pow(p.x - q.x, 2) + Math.pow(p.y - q.y, 2))
        if (el.matches('.mkaps-sentence')) {
          const r = Math.max(30 / p.elSize, Math.min(2000 / p.elSize, len1 / len0))
          el.style.left = `${p.x - Math.round((p.originX - p.elX) * r)}px`
          el.style.top = `${p.y - Math.round((p.originY - p.elY) * r)}px`
          el.style.fontSize = `${Math.round(p.elSize * r)}px`
        } else if (el.matches('.mkaps-image') || el.matches('.mkaps-avatar') || el.matches('.mkaps-video')) {
          const r = len1 / len0
          el.style.left = `${p.x - Math.round((p.originX - p.elX) * r)}px`
          el.style.top = `${p.y - Math.round((p.originY - p.elY) * r)}px`
          el.style.width = `${Math.round(p.elSize * r)}px`
        }
      }
    }

    const commit = () => {
      if (!timeout) return
      timeout = null
      if (pointers.length == 1) {
        const p = pointers[0]
        // is State 2
        if (el.id == 'board') {
          p.originX = p.x
          p.originY = p.y
          p.origins = new Map()
          setAllOrigins(p.origins)
          const events = persistent(el)
          if (events.length > 0) this.pushEvent('commit', events)
        } else if (draggings.has(el)) {
          p.originX = p.x
          p.originY = p.y
          p.elX = parseInt(el.style.left, 10)
          p.elY = parseInt(el.style.top, 10)
          p.elZ = parseInt(el.style.zIndex, 10)
          p.elSize = getSize(el)
          this.pushEvent('commit', [xyzSize(el)])
        }
      } else  {
        const p = pointers[0]
        const q = pointers[1]
        // is State 3
        if (el.id == 'board') {
          p.originX = p.x
          p.originY = p.y
          p.origins = new Map()
          setAllOrigins(p.origins)
          q.originX = q.x
          q.originY = q.y
          const events = persistent(el)
          if (events.length > 0) this.pushEvent('commit', events)
        } else {
          p.originX = p.x
          p.originY = p.y
          p.elX = parseInt(el.style.left, 10)
          p.elY = parseInt(el.style.top, 10)
          p.elZ = parseInt(el.style.zIndex, 10)
          p.elSize = getSize(el)
          q.originX = q.x
          q.originY = q.y
          this.pushEvent('commit', [xyzSize(el)])
        }
      }
    }

    window.addEventListener('pointermove', (e) => {
      // invalidate pointers
      if (myTicker != ticker) {
        myTicker = ticker
        pointers.splice(0)
      }
      const i = pointers.findIndex(p => p.pointerId == e.pointerId)
      if (i == -1) return

      const p = pointers[i]
      p.x = e.x
      p.y = e.y
      if (!pointers[0].moved) {
        // is State 1
        p.moved ||= Math.abs(e.x - p.originX) >= 10
        p.moved ||= Math.abs(e.y - p.originY) >= 10
        if (!p.moved) return
        if (el.id == 'board') {
          p.originX = p.x
          p.originY = p.y
          p.origins = new Map()
          setAllOrigins(p.origins)
        } else {
          p.originX = p.x
          p.originY = p.y
          p.elX = parseInt(el.style.left, 10)
          p.elY = parseInt(el.style.top, 10)
          p.elZ = parseInt(el.style.zIndex, 10)
          p.elSize = getSize(el)
        }
        if (pointers.length == 1) return
        if (document.querySelector('#board.mkaps-toggle-zoom') ||
            document.querySelector('#board.mkaps-toggle-rotate')) {
          // be State 3
          pointers.splice(i, 1)
          pointers.unshift(p)
          pointers.splice(2)
          pointers[1].moved = true
        } else {
          // be State 2
          pointers.splice(1)
        }
      }
      if (!document.querySelector('#board.mkaps-toggle-pan')) return
      if (el.id != 'board' && !el.matches('.mkaps-drag')) return
      if ((el.id == 'board') !=
          (document.querySelector('#board.mkaps-toggle-sentences') != null ||
           document.querySelector('#board.mkaps-toggle-images') != null)) return
      if (pointers.length == 1) {
        singleTouch()
      } else {
        multiTouch()
      }
      timeout = timeout || setTimeout(commit, 100)
    })
  }
}

Hooks.Canvas = {
  mounted() {
    const el = this.el
    const ctx = el.getContext('2d')
    ctx.lineCap = 'round'
    const staticCanvas = document.getElementById('static-canvas')
    const staticCtx = staticCanvas.getContext('2d')
    staticCtx.lineCap = 'round'

    const dynamicLineWidth = (prevWidth, prev, [t, x, y]) => {
      const dt = Math.max(1, t - prev[0])
      const dx = x - prev[1]
      const dy = y - prev[2]
      const dist = Math.max(1, Math.sqrt(dx * dx + dy * dy))
      const speed = dist / dt
      const maxWidth = el.dataset.strokeWidth
      const minWidth = 1
      const sensitiveToSpeed = 0.5
      const sensitiveToDiffuse = 0.3

      const target = minWidth + maxWidth * sensitiveToDiffuse / (sensitiveToDiffuse + Math.pow(speed, sensitiveToSpeed))
      if (!prevWidth) return target
      return 0.7 * prevWidth + 0.3 * target
    }

    const dpr = 3
    const drawStroke = (ctx, width, prev, [t, x, y]) => {
      if (x == prev[1] && y == prev[2]) {
        ctx.beginPath()
        ctx.arc(x * el.dataset.dr + el.dataset.dx * dpr, y * el.dataset.dr + el.dataset.dy * dpr, width / 2, 0, 2 * Math.PI)
        ctx.fill()
      } else {
        ctx.lineWidth = width
        ctx.beginPath()
        ctx.moveTo(prev[1] * el.dataset.dr + el.dataset.dx * dpr, prev[2] * el.dataset.dr + el.dataset.dy * dpr)
        ctx.lineTo(x * el.dataset.dr + el.dataset.dx * dpr, y * el.dataset.dr + el.dataset.dy * dpr)
        ctx.stroke()
      }
    }

    // [{t0,style,txys:[[t,x,y]]}]
    const slideStrokes = new Map()
    const slideKnob = new Map()

    let playTimeout = null
    let repeatTimeout = null

    const strokesToKnobs = (strokes) => {
      const m = new Map()
      let max = null
      for (const stroke of strokes) {
        if (stroke.style == 'erased') continue
        m.set(stroke.t0 + stroke.txys[0][0], stroke.style)
      }
      const knobs = Array.from(m)
      knobs.sort(([t0, s0], [t1, s1]) => t0 - t1)
      return knobs
    }

    const staticRedraw = () => {
      clearTimeout(repeatTimeout)
      cancelAnimationFrame(playTimeout)
      playTimeout = null
      staticCtx.clearRect(0, 0, el.width, el.height)
      const strokes = slideStrokes.get(el.dataset.slideId)
      if (!strokes) return
      const knobs = strokesToKnobs(strokes)
      let knob = knobs.length
      if (slideKnob.has(el.dataset.slideId)) knob = slideKnob.get(el.dataset.slideId)
      for (const stroke of strokes) {
        if (stroke.style == 'erased') continue
        staticCtx.strokeStyle = stroke.style
        staticCtx.fillStyle = stroke.style
        let prev = stroke.txys[0]
        let width = 0
        for (const [t,x,y] of stroke.txys.slice(1)) {
          if (knob < knobs.length && knobs[knob][0] <= stroke.t0 + t) {
            staticCtx.strokeStyle = "oklch(70.7% 0.022 261.325)"
            staticCtx.fillStyle = "oklch(70.7% 0.022 261.325)"
          }
          width = dynamicLineWidth(width, prev, [t,x,y])
          drawStroke(staticCtx, width, prev, [t,x,y])
          prev = [t,x,y]
        }
      }
      for (const [x,y] of erasers.values()) {
        staticCtx.fillStyle = '#ffffff'
        staticCtx.beginPath()
        staticCtx.arc(x, y, el.dataset.strokeWidth / 2, 0, 2 * Math.PI)
        staticCtx.fill()
      }
    }

    const touchEraser = (px, py, x, y, ex, ey, width) => {
      const r = (Number(el.dataset.strokeWidth) + width) / 2
      const [ux, uy] = [px - x, py - y]
      const [vx, vy] = [ex - x, ey - y]
      const [wx, wy] = [ex - px, ey - py]
      const uu = ux*ux + uy*uy
      const vv = vx*vx + vy*vy
      const ww = wx*wx + wy*wy
      const cross = ux*vy - uy*vx

      if (vv <= r*r || ww <= r*r) return true

      if (uu && cross*cross > r*r * uu) return false
      if (!uu && vv > r*r) return false

      if (ux*vx + uy*vy < 0 || -ux*wx + -uy*wy < 0) return false

      return true
    }

    const erase = (ex, ey) => {
      const strokes = slideStrokes.get(el.dataset.slideId)
      if (!strokes) return
      for (const stroke of strokes) {
        let prev = stroke.txys[0]
        let width = 0
        for (const [t,x,y] of stroke.txys.slice(1)) {
          width = dynamicLineWidth(width, prev, [t,x,y])
          if (touchEraser(prev[1], prev[2], x, y, ex, ey, width)) {
            stroke.style = 'erased'
            break
          }
          prev = [t,x,y]
        }
      }
      if (strokes.length == 0) slideStrokes.delete(el.dataset.slideId)
      const knobs = strokesToKnobs(strokes)
      slideKnob.delete(el.dataset.slideId)
      this.pushEvent('seeked', {knob: knobs.length, knobs: knobs})
      staticRedraw()
    }

    const erasers = new Map()
    const drawingStrokes = new Map()
    const drawingStrokeWidths = new Map()
    const diffuseTimeouts = new Map()
    let latestPointerEnd = null
    const diffuse = (id) => {
      diffuseTimeouts.delete(id)
      if (!drawingStrokes.size) {
        ctx.clearRect(0, 0, el.width, el.height)
        return
      }
      const stroke = drawingStrokes.get(id)
      if (!stroke) return
      const p = stroke.txys[stroke.txys.length-1]
      const width = dynamicLineWidth(0, p, [Date.now() - stroke.begin, p[1], p[2]])
      ctx.fillStyle = stroke.style
      ctx.beginPath()
      ctx.arc(p[1] * el.dataset.dr + el.dataset.dx * dpr, p[2] * el.dataset.dr + el.dataset.dy * dpr, width / 2, 0, 2 * Math.PI)
      ctx.fill()
      diffuseTimeouts.set(id, setTimeout(() => diffuse(id), 30))
    }

    el.addEventListener('pointerdown', (e) => {
      if (el.dataset.color === undefined) return
      if (el.dataset.color == "eraser") {
        erasers.set(e.pointerId, [e.x*dpr, e.y*dpr])
        erase(e.x*dpr, e.y*dpr)
        return
      }
      const stroke = {
        t0: 0,
        begin: Date.now(),
        style: el.dataset.color,
        txys: [[0, e.x*dpr, e.y*dpr]]
      }
      const strokes = slideStrokes.get(el.dataset.slideId)
      if (latestPointerEnd) {
        const prevStroke = strokes[strokes.length-1]
        stroke.t0 = prevStroke.t0 + prevStroke.txys[prevStroke.txys.length-1][0]
        stroke.t0 += Math.min(1000, stroke.begin - latestPointerEnd)
      } else if (strokes) {
        const knobs = strokesToKnobs(strokes)
        let knob = knobs.length
        if (slideKnob.has(el.dataset.slideId)) knob = slideKnob.get(el.dataset.slideId)
        if (knob < knobs.length) {
          stroke.t0 = knobs[knob][0]
        } else {
          stroke.t0 = Math.max(...strokes.map((s) => s.t0 + s.txys[s.txys.length-1][0]))
        }
      }
      drawingStrokes.set(e.pointerId, stroke)
      diffuseTimeouts.set(e.pointerId, setTimeout(() => diffuse(e.pointerId), 30))
    })
    window.addEventListener('pointermove', (e) => {
      if (erasers.has(e.pointerId)) {
        erasers.set(e.pointerId, [e.x*dpr, e.y*dpr])
        erase(e.x*dpr, e.y*dpr)
        return
      }
      const stroke = drawingStrokes.get(e.pointerId)
      if (!stroke) return
      const prev = stroke.txys[stroke.txys.length-1]
      const curr = [Date.now() - stroke.begin, e.x*dpr, e.y*dpr]
      stroke.txys.push(curr)
      ctx.strokeStyle = stroke.style
      const width = dynamicLineWidth(drawingStrokeWidths.get(e.pointerId) || 0, prev, curr)
      drawingStrokeWidths.set(e.pointerId, width)
      drawStroke(ctx, width, prev, curr)
      clearTimeout(diffuseTimeouts.get(e.pointerId))
      diffuseTimeouts.set(e.pointerId, setTimeout(() => diffuse(e.pointerId), 30))
    })
    const pointerend = (e) => {
      if (erasers.has(e.pointerId)) {
        erasers.delete(e.pointerId)
        erase(e.x*dpr, e.y*dpr)
        return
      }
      const stroke = drawingStrokes.get(e.pointerId)
      if (!stroke) return
      drawingStrokes.delete(e.pointerId)
      drawingStrokeWidths.delete(e.pointerId)
      latestPointerEnd = Date.now()
      stroke.txys.push([latestPointerEnd - stroke.begin, e.x*dpr, e.y*dpr])
      delete stroke.begin
      if (!slideStrokes.has(el.dataset.slideId)) slideStrokes.set(el.dataset.slideId, [])
      const strokes = slideStrokes.get(el.dataset.slideId)
      strokes.push(stroke)
      const knobs = strokesToKnobs(strokes)
      const knob = knobs.findIndex(([t, s]) => t >= stroke.t0 + stroke.txys[stroke.txys.length-1][0])
      if (knob == -1) {
        slideKnob.delete(el.dataset.slideId)
        this.pushEvent('seeked', {knob: knobs.length, knobs: knobs})
      } else {
        slideKnob.set(el.dataset.slideId, knob)
        this.pushEvent('seeked', {knob: knob, knobs: knobs})
      }
      staticRedraw()
    }
    window.addEventListener('pointerup', pointerend)
    window.addEventListener('pointercancel', pointerend)

    this.handleEvent('seek', ({knob}) => {
      latestPointerEnd = null
      slideKnob.set(el.dataset.slideId, knob)
      staticRedraw()
    })
    this.handleEvent('terminate', () => {
      const strokes = slideStrokes.get(el.dataset.slideId)
      if (!strokes) return
      if (!slideKnob.has(el.dataset.slideId)) return
      const knob = slideKnob.get(el.dataset.slideId)
      const knobs = strokesToKnobs(strokes)
      if (knob == knobs.length) return
      slideKnob.delete(el.dataset.slideId)
      if (knob == 0) {
        slideStrokes.delete(el.dataset.slideId)
        staticRedraw()
        this.pushEvent('seeked', {knob: null, knobs: null})
      } else {
        const newStrokes = strokes.filter((s) => s.t0 + s.txys[0][0] < knobs[knob][0])
        const newKnobs = strokesToKnobs(newStrokes)
        slideStrokes.set(el.dataset.slideId, newStrokes)
        staticRedraw()
        this.pushEvent('seeked', {knob: knob, knobs: newKnobs})
      }
    })
    this.handleEvent('play', ({knob}) => {
      const strokes = slideStrokes.get(el.dataset.slideId)
      if (!strokes) return
      const knobs = strokesToKnobs(strokes)

      const commands = []
      for (const stroke of strokes) {
        if (stroke.style == 'erased') continue
        let prev = stroke.txys[0]
        let width = 0
        for (const [t,x,y] of stroke.txys.slice(1)) {
          width = dynamicLineWidth(width, prev, [t,x,y])
          commands.push([stroke.t0 + t, stroke.style, width, prev, [t,x,y]])
          prev = [t,x,y]
        }
      }
      commands.sort((a, b) => a[0] - b[0])

      let i = commands.length
      let begin = null
      const step = (t) => {
        if (i == commands.length) {
          i = 0
          begin = t
          if (knob < knobs.length) begin -= knobs[knob][0]
          staticCtx.clearRect(0, 0, el.width, el.height)
          for (const stroke of strokes) {
            if (stroke.style == 'erased') continue
            staticCtx.strokeStyle = "oklch(70.7% 0.022 261.325)"
            staticCtx.fillStyle = "oklch(70.7% 0.022 261.325)"
            let prev = stroke.txys[0]
            let width = 0
            for (const [t,x,y] of stroke.txys.slice(1)) {
              width = dynamicLineWidth(width, prev, [t,x,y])
              drawStroke(staticCtx, width, prev, [t,x,y])
              prev = [t,x,y]
            }
          }
        }
        while (i < commands.length && t - begin >= commands[i][0]) {
          staticCtx.strokeStyle = commands[i][1]
          staticCtx.fillStyle = commands[i][1]
          const width = commands[i][2]
          const prev = commands[i][3]
          const curr = commands[i][4]
          drawStroke(staticCtx, width, prev, curr)
          i++
        }
        if (i == commands.length) {
          playTimeout = null
          repeatTimeout = setTimeout(() => {
            playTimeout = playTimeout || requestAnimationFrame(step)
          }, 1000)
        } else {
          playTimeout = requestAnimationFrame(step)
        }
      }
      clearTimeout(repeatTimeout)
      cancelAnimationFrame(playTimeout)
      playTimeout = requestAnimationFrame(step)
    })
    this.handleEvent('redraw', () => {
      latestPointerEnd = null
      staticRedraw()
      const strokes = slideStrokes.get(el.dataset.slideId)
      if (!strokes) return
      const knobs = strokesToKnobs(strokes)
      let knob = knobs.length
      if (slideKnob.has(el.dataset.slideId)) knob = slideKnob.get(el.dataset.slideId)
      this.pushEvent('seeked', {knob: knob, knobs: knobs})
    })
  }
}

Hooks.IdleDisconnect = {
  mounted() {
    let idleTimeout

    const resetTimer = () => {
      clearTimeout(idleTimeout)
      idleTimeout = setTimeout(() => {
        this.pushEvent("idle_disconnect", {})
      }, 20 * 60 * 1000)
    }

    resetTimer()
    window.addEventListener('pointerdown', resetTimer)
    window.addEventListener('pointermove', resetTimer)
  }
}

Hooks.CopyOnClick = {
  mounted() {
    this.el.addEventListener("click", () => {
      const text = this.el.dataset.copyText
      navigator.clipboard.writeText(text).then(() => {
        this.el.classList.add("text-success")
        setTimeout(() => this.el.classList.remove("text-success"), 1000)
      })
    })
  }
}

Hooks.FullScreen = {
  mounted() {
    this.el.addEventListener('click', () => {
      if (document.fullscreenElement) {
        document.exitFullscreen?.()
      } else {
        document.documentElement.requestFullscreen?.()
      }
    })
  }
}

Hooks.Experiment = {
  mounted() {
    const el = this.el
    const ctx = el.getContext('2d')
    const strokes = []
    const redraw = () => {
      ctx.clearRect(0, 0, el.width, el.height)
      ctx.lineCap = 'round'
      ctx.strokeStyle = '#00ff00'
      ctx.lineWidth = 20
      ctx.beginPath()
      ctx.moveTo(strokes[0][0]*3, strokes[0][1]*3)
      for (const stroke of strokes.slice(1)) {
        ctx.lineTo(stroke[0]*3, stroke[1]*3)
      }
      ctx.stroke()
    }
    window.addEventListener('touchstart', (e) => {
      strokes.push([e.touches[0].clientX, e.touches[0].clientY])
      redraw()
    })
    window.addEventListener('pointermove', (e) => {
      strokes.push([e.clientX, e.clientY])
      redraw()
    })
  }
}

Hooks.Pad = {
  mounted() {
    const el = this.el
    const ctx = el.getContext('2d')
    ctx.lineCap = 'round'

    const dpr = 2
    const drawStroke = (ctx, width, prev, [t, x, y]) => {
      if (x == prev[1] && y == prev[2]) {
        ctx.beginPath()
        ctx.arc(x, y, width / 2, 0, 2 * Math.PI)
        ctx.fill()
      } else {
        ctx.lineWidth = width
        ctx.beginPath()
        ctx.moveTo(prev[1], prev[2])
        ctx.lineTo(x, y)
        ctx.stroke()
      }
    }

    let activeId = null
    const strokes = []
    let stroke = null

    const colors = [
      "oklch(63.7% 0.237 25.331)",
      "oklch(75% 0.183 55.934)",
      "oklch(90.5% 0.182 98.111)",
      "oklch(72.3% 0.219 149.579)",
      "oklch(62.3% 0.214 259.815)",
      "oklch(62.7% 0.265 303.9)"
    ]

    el.addEventListener('pointerdown', (e) => {
      if (activeId) return
      activeId = e.pointerId
      const rect = el.getBoundingClientRect()
      console.log(`${e.y} ${rect.top}`)
      stroke = {
        t0: 0,
        begin: Date.now(),
        style: colors[strokes.length % colors.length],
        txys: [[0, (e.x - rect.left)*dpr, (e.y - rect.top)*dpr]]
      }
    })
    window.addEventListener('pointermove', (e) => {
      if (activeId != e.pointerId) return
      const rect = el.getBoundingClientRect()
      const prev = stroke.txys[stroke.txys.length-1]
      const curr = [Date.now() - stroke.begin, (e.x - rect.left)*dpr, (e.y - rect.top)*dpr]
      stroke.txys.push(curr)
      ctx.fillStyle = stroke.style
      ctx.strokeStyle = stroke.style
      drawStroke(ctx, 30, prev, curr)
    })
    const pointerend = (e) => {
      if (activeId != e.pointerId) return
      const rect = el.getBoundingClientRect()
      stroke.txys.push([Date.now() - stroke.begin, (e.x - rect.left)*dpr, (e.y - rect.top)*dpr])
      delete stroke.begin
      strokes.push(stroke)
      stroke = null
      activeId = null
    }
    window.addEventListener('pointerup', pointerend)
    window.addEventListener('pointercancel', pointerend)

    this.handleEvent('clear', () => {
      ctx.clearRect(0, 0, el.width, el.height)
      strokes.splice(0)
    })
    this.handleEvent('request_submit', () => {
      this.pushEvent('submit', strokes)
    })

    this.pushEvent('init')
    this.handleEvent('init', (saved) => {
      strokes.splice(0, Infinity, ...saved.list)
      ctx.clearRect(0, 0, el.width, el.height)
      for (const stroke of strokes) {
        ctx.fillStyle = stroke.style
        ctx.strokeStyle = stroke.style
        let prev = stroke.txys[0]
        for (const [t,x,y] of stroke.txys.slice(1)) {
          drawStroke(ctx, 30, prev, [t,x,y])
          prev = [t,x,y]
        }
      }
    })
  }
}

Hooks.SmallPad = {
  mounted() {
    const el = this.el
    const ctx = el.getContext('2d')
    ctx.lineCap = 'round'

    const dpr = 2
    const drawStroke = (ctx, width, prev, [t, x, y]) => {
      if (x == prev[1] && y == prev[2]) {
        ctx.beginPath()
        ctx.arc(x, y, width / 2, 0, 2 * Math.PI)
        ctx.fill()
      } else {
        ctx.lineWidth = width
        ctx.beginPath()
        ctx.moveTo(prev[1], prev[2])
        ctx.lineTo(x, y)
        ctx.stroke()
      }
    }

    const colors = [
      "oklch(63.7% 0.237 25.331)",
      "oklch(75% 0.183 55.934)",
      "oklch(90.5% 0.182 98.111)",
      "oklch(72.3% 0.219 149.579)",
      "oklch(62.3% 0.214 259.815)",
      "oklch(62.7% 0.265 303.9)"
    ]

    this.pushEvent('smallpad-init', {
      id: el.dataset.id
    })
    this.handleEvent('draw', (pad) => {
      if (pad.id != el.dataset.id) return
      ctx.clearRect(0, 0, el.width, el.height)
      for (const stroke of pad.strokes.list) {
        ctx.fillStyle = stroke.style
        ctx.strokeStyle = stroke.style
        let prev = stroke.txys[0]
        for (const [t,x,y] of stroke.txys.slice(1)) {
          drawStroke(ctx, 30, prev, [t,x,y])
          prev = [t,x,y]
        }
      }
    })
  }
}

export default Hooks
