const Hooks = {}

const draggings = new Set()
let ticker = 1

const getSize = (el) => {
  if (el.matches('.mkaps-sentence')) return parseInt(el.style.fontSize, 10)
  if (el.matches('.mkaps-image')) return parseInt(el.style.width, 10)
  if (el.matches('.mkaps-avatar')) return parseInt(el.style.width, 10)
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
  }
  return events
}

Hooks.Touchable = {
  mounted() {
    const el = this.el
    let myTicker = 1
    let timeout = null

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
        }
      } else {
        const len0 = Math.sqrt(Math.pow(p.originX - q.originX, 2) + Math.pow(p.originY - q.originY, 2))
        const len1 = Math.sqrt(Math.pow(p.x - q.x, 2) + Math.pow(p.y - q.y, 2))
        if (el.matches('.mkaps-sentence')) {
          const r = Math.max(30 / p.elSize, Math.min(200 / p.elSize, len1 / len0))
          el.style.left = `${p.x - Math.round((p.originX - p.elX) * r)}px`
          el.style.top = `${p.y - Math.round((p.originY - p.elY) * r)}px`
          el.style.fontSize = `${Math.round(p.elSize * r)}px`
        } else if (el.matches('.mkaps-image') || el.matches('.mkaps-avatar')) {
          const r = Math.max(100 / p.elSize, Math.min(1080 / p.elSize, len1 / len0))
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
      const maxWidth = 30
      const minWidth = 1
      const responsiveToSpeed = 0.5
      const responsiveToDiffuse = 0.3

      const target = minWidth + maxWidth * responsiveToDiffuse / (responsiveToDiffuse + Math.pow(speed, responsiveToSpeed))
      if (!prevWidth) return target
      return 0.3 * prevWidth + 0.7 * target
    }

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

    const slideStrokes = new Map()
    const slideKnob = new Map()

    const staticRedraw = () => {
      staticCtx.clearRect(0, 0, el.width, el.height)
      const knob = slideKnob.get(el.dataset.slideId)
      for (const stroke of slideStrokes.get(el.dataset.slideId) || []) {
        staticCtx.strokeStyle = stroke[0][1]
        staticCtx.fillStyle = stroke[0][1]
        let prev = stroke[1]
        let width = 0
        for (const [t,x,y] of stroke.slice(2)) {
          if (knob && knob[1] < t - stroke[0][0]) return
          width = dynamicLineWidth(width, prev, [t,x,y])
          drawStroke(staticCtx, width, prev, [t, x, y])
          prev = [t,x,y]
        }
      }
    }

    const strokings = new Map()
    let timeout = null
    const diffuse = () => {
      for (const stroke of strokings.values()) {
        const p = stroke[stroke.length-1]
        const width = dynamicLineWidth(0, p, [Date.now(), p[1], p[2]])
        ctx.fillStyle = stroke[0][1]
        ctx.beginPath()
        ctx.arc(p[1], p[2], width / 2, 0, 2 * Math.PI)
        ctx.fill()
      }
      if (strokings.size) {
        timeout = setTimeout(diffuse, 30)
      } else {
        timeout = null
        ctx.clearRect(0, 0, el.width, el.height)
      }
    }

    const dpr = 3
    el.addEventListener('pointerdown', (e) => {
      if (el.dataset.color === undefined) return
      strokings.set(e.pointerId, [[null, el.dataset.color], [Date.now(), e.x*dpr, e.y*dpr]])
      timeout = timeout || setTimeout(diffuse, 0)
    })
    window.addEventListener('pointermove', (e) => {
      const stroke = strokings.get(e.pointerId)
      if (!stroke) return
      const prev = stroke[stroke.length-1]
      const curr = [Date.now(), e.x*dpr, e.y*dpr]
      const width = dynamicLineWidth(0, prev, curr)
      ctx.strokeStyle = stroke[0][1]
      drawStroke(ctx, width, prev, curr)
      stroke.push(curr)
      clearTimeout(timeout)
      timeout = setTimeout(diffuse, 30)
    })
    const pointerend = (e) => {
      const stroke = strokings.get(e.pointerId)
      if (!stroke) return
      stroke.push([Date.now(), e.x*dpr, e.y*dpr])

      const strokes = slideStrokes.get(el.dataset.slideId) || []
      const knob = slideKnob.get(el.dataset.slideId)
      if (knob) {
        if (knob[1] == 0) {
          strokes.splice(0)
        } else {
          strokes.splice(knob[0] + 1)
        }
      }

      const lastStroke = strokes[strokes.length-1]
      if (lastStroke) {
        while (knob && lastStroke[lastStroke.length-1][0] - lastStroke[0][0] > knob[1]) lastStroke.pop()
        const t0 = lastStroke[lastStroke.length-1][0] + 1000
        stroke[0][0] = Math.max(0, stroke[1][0] - t0) + lastStroke[0][0]
      } else {
        stroke[0][0] = stroke[1][0] - 1
      }
      const maxSeek = stroke[stroke.length-1][0] - stroke[0][0]
      this.pushEvent('seeked', {knob: maxSeek, max_seek: maxSeek})

      strokes.push(stroke)
      slideStrokes.set(el.dataset.slideId, strokes)
      slideKnob.delete(el.dataset.slideId)
      strokings.delete(e.pointerId)
      staticRedraw()
    }
    window.addEventListener('pointerup', pointerend)
    window.addEventListener('pointercancel', pointerend)

    this.handleEvent('undo', () => {
      const strokes = slideStrokes.get(el.dataset.slideId)
      if (!strokes) return
      const [i, _t] = slideKnob.get(el.dataset.slideId) || [strokes.length-1, null]
      let knob = [0, 0]
      if (i > 0) {
        const stroke = strokes[i-1]
        knob = [i-1, stroke[stroke.length-1][0] - stroke[0][0]]
      }
      slideKnob.set(el.dataset.slideId, knob)
      this.pushEvent('seeked', {knob: knob[1]})
      staticRedraw()
    })
    this.handleEvent('redo', () => {
      const strokes = slideStrokes.get(el.dataset.slideId)
      if (!strokes) return
      let [i, t] = slideKnob.get(el.dataset.slideId) || [strokes.length-1, null]
      if (t > 0) i = Math.min(strokes.length-1, i + 1)
      const stroke = strokes[i]
      const knob = [i, stroke[stroke.length-1][0] - stroke[0][0]]
      slideKnob.set(el.dataset.slideId, knob)
      this.pushEvent('seeked', {knob: knob[1]})
      staticRedraw()
    })
    this.handleEvent('seek', ({knob}) => {
      const strokes = slideStrokes.get(el.dataset.slideId)
      if (!strokes) return
      let i = 0
      while (true) {
        const stroke = strokes[i]
        if (knob <= stroke[stroke.length-1][0] - stroke[0][0]) break
        i++
      }
      slideKnob.set(el.dataset.slideId, [i, knob])
      staticRedraw()
    })
    this.handleEvent('redraw', () => {
      staticRedraw()
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
    window.addEventListener('pointerdown', () => resetTimer())
    window.addEventListener('pointermove', () => resetTimer())
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

export default Hooks
