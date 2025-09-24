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
          if (events.length > 0) this.pushEvent('drags', events)
        } else if (draggings.has(el)) {
          p.originX = p.x
          p.originY = p.y
          p.elX = parseInt(el.style.left, 10)
          p.elY = parseInt(el.style.top, 10)
          p.elZ = parseInt(el.style.zIndex, 10)
          p.elSize = getSize(el)
          this.pushEvent('drags', [xyzSize(el)])
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
          if (events.length > 0) this.pushEvent('drags', events)
        } else {
          p.originX = p.x
          p.originY = p.y
          p.elX = parseInt(el.style.left, 10)
          p.elY = parseInt(el.style.top, 10)
          p.elZ = parseInt(el.style.zIndex, 10)
          p.elSize = getSize(el)
          q.originX = q.x
          q.originY = q.y
          this.pushEvent('drags', [xyzSize(el)])
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
      if (!timeout) timeout = setTimeout(commit, 100)
    })
  }
}

const slideStrokes = new Map()

Hooks.Canvas = {
  mounted() {
    const el = this.el
    const ctx = el.getContext('2d')
    const strokings = new Map()
    const undoes = []
    let timeout = null
    const dynamicLineWidth = (ink, prev, [t,x,y]) => {
      const dist = Math.sqrt(Math.pow(x - prev[1], 2) + Math.pow(y - prev[2], 2))
      const clamp = Math.min(20, dist)
      return Math.min(50, 15 * (5 + 10 * Math.log((t - prev[0]) * 0.1 + 1)) / (20 + clamp))
    }
    const redraw = () => {
      timeout = null
      ctx.clearRect(0, 0, el.width, el.height)
      ctx.lineCap = 'round'
      for (const stroke of slideStrokes.get(el.dataset.slideId) || []) {
        ctx.strokeStyle = stroke[0]
        let prev = stroke[1]
        let ink = 0
        for (const [t,x,y] of stroke.slice(2)) {
          ctx.lineWidth = ink = dynamicLineWidth(ink, prev, [t,x,y])
          ctx.beginPath()
          ctx.moveTo(prev[1]*3, prev[2]*3)
          ctx.lineTo(x*3, y*3)
          ctx.stroke()
          prev = [t,x,y]
        }
      }
      for (const stroke of strokings.values()) {
        ctx.strokeStyle = stroke[0]
        let prev = stroke[1]
        let ink = 0
        for (const [t,x,y] of stroke.slice(2)) {
          ctx.lineWidth = ink = dynamicLineWidth(ink, prev, [t,x,y])
          ctx.beginPath()
          ctx.moveTo(prev[1]*3, prev[2]*3)
          ctx.lineTo(x*3, y*3)
          ctx.stroke()
          prev = [t,x,y]
        }
        ctx.lineWidth = dynamicLineWidth(ink, prev, [Date.now(),prev[1],prev[2]])
        ctx.beginPath()
        ctx.moveTo(prev[1]*3, prev[2]*3)
        ctx.lineTo(prev[1]*3, prev[2]*3)
        ctx.stroke()
      }
      if (strokings.size > 0) timeout = setTimeout(redraw, 100)
    }
    el.addEventListener('pointerdown', (e) => {
      if (el.dataset.color === undefined) return
      strokings.set(e.pointerId, [el.dataset.color, [Date.now(), e.x, e.y]])
      if (!timeout) timeout = setTimeout(redraw, 0)
    })
    window.addEventListener('pointermove', (e) => {
      if (!strokings.has(e.pointerId)) return
      strokings.get(e.pointerId).push([Date.now(), e.x, e.y])
      clearTimeout(timeout)
      setTimeout(redraw, 0)
    })
    const pointerend = (e) => {
      if (!strokings.has(e.pointerId)) return
      const stroke = strokings.get(e.pointerId)
      stroke.push([Date.now(), e.x, e.y])
      if (!slideStrokes.has(el.dataset.slideId)) slideStrokes.set(el.dataset.slideId, [])
      slideStrokes.get(el.dataset.slideId).push(stroke)
      strokings.delete(e.pointerId)
      undoes.splice(0)
      clearTimeout(timeout)
      setTimeout(redraw, 0)
    }
    window.addEventListener('pointerup', pointerend)
    window.addEventListener('pointercancel', pointerend)
    this.handleEvent('undo', () => {
      const stroke = slideStrokes.get(el.dataset.slideId)?.pop()
      if (!stroke) return
      undoes.push(stroke)
      if (!timeout) timeout = setTimeout(redraw, 0)
    })
    this.handleEvent('redo', () => {
      if (undoes.length == 0) return
      slideStrokes.get(el.dataset.slideId).push(undoes.pop())
      if (!timeout) timeout = setTimeout(redraw, 0)
    })
    this.handleEvent('redraw', () => {
      if (!timeout) timeout = setTimeout(redraw, 0)
    })
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

export default Hooks
