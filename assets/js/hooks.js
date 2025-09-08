const Hooks = {}

const sentenceOrigins = new Map()
const imageOrigins = new Map()

Hooks.Touchable = {
  mounted() {
    const el = this.el
    const touches = []
    let touchended = 0
    let cachedEls = new Set()

    if (el.matches('.mkaps-sentence')) {
      sentenceOrigins.set(el, {
        x: parseInt(el.style.left, 10),
        y: parseInt(el.style.top, 10),
        fontSize: parseInt(el.style.fontSize, 10)
      })
    }
    if (el.matches('.mkaps-image')) {
      imageOrigins.set(el, {
        x: parseInt(el.style.left, 10),
        y: parseInt(el.style.top, 10),
        height: parseInt(el.style.height, 10)
      })
    }

    const getSize = (el) => {
      if (el.matches('.mkaps-sentence')) return parseInt(el.style.fontSize, 10)
      if (el.matches('.mkaps-image')) return parseInt(el.style.height, 10)
    }

    const touchStart = (identifier, point) => {
      if (el.id == 'background') {
        cachedEls = new Set(sentenceOrigins.keys()).union(new Set(imageOrigins.keys()))
      } else if (el.matches('.mkaps-sentence')) {
        sentenceOrigins.delete(el)
      } else if (el.matches('.mkaps-image')) {
        imageOrigins.delete(el)
      }
      touches.push({
        isMain: touches.length < 2,
        moved: false,
        identifier: identifier,
        origin: {
          x: point.clientX,
          y: point.clientY
        },
        elOrigin: {
          x: parseInt(el.style.left, 10),
          y: parseInt(el.style.top, 10),
          fontSize: parseInt(el.style.fontSize, 10),
          height: parseInt(el.style.height, 10)
        },
        x: point.clientX,
        y: point.clientY
      })
      el.style.cursor = "grabbing"

      // so that tap highlight would not reset xyz
      if (el.matches('.mkaps-drag')) {
        this.pushEvent("drag", {
          item: el.id,
          x: parseInt(el.style.left, 10),
          y: parseInt(el.style.top, 10),
          z: parseInt(el.style.zIndex, 10),
          size: getSize(el)
        })
      }
    }

    const touchMove = (identifier, point) => {
      const t = touches.find(t => t.identifier == identifier)
      if (!t) return false
      t.x = point.clientX
      t.y = point.clientY
      const moved = t.moved
      t.moved ||= Math.abs(t.x - t.origin.x) >= 10
      t.moved ||= Math.abs(t.y - t.origin.y) >= 10
      if (!moved && t.moved && el.matches('.mkaps-touch-drag')) {
        // quite unpredictable, but efficient
        const allZ = Array.from(document.querySelectorAll('.mkaps-touch-drag')).map(e => e.style.zIndex);
        el.style.zIndex = Math.max(...allZ) + 1
      }
      return t.moved && t.isMain
    }

    const pinchSentence = (t0, t1) => {
      const len0 = Math.sqrt(Math.pow(t0.origin.x - t1.origin.x, 2) + Math.pow(t0.origin.y - t1.origin.y, 2))
      const len1 = Math.sqrt(Math.pow(t0.x - t1.x, 2) + Math.pow(t0.y - t1.y, 2))
      el.style.left = `${t0.x - Math.round((t0.origin.x - t0.elOrigin.x) * len1 / len0)}px`
      el.style.top = `${t0.y - Math.round((t0.origin.y - t0.elOrigin.y) * len1 / len0)}px`
      el.style.fontSize = `${Math.round(t0.elOrigin.fontSize * len1 / len0)}px`
    }

    const pinchImage = (t0, t1) => {
      const len0 = Math.sqrt(Math.pow(t0.origin.x - t1.origin.x, 2) + Math.pow(t0.origin.y - t1.origin.y, 2))
      const len1 = Math.sqrt(Math.pow(t0.x - t1.x, 2) + Math.pow(t0.y - t1.y, 2))
      el.style.left = `${t0.x - Math.round((t0.origin.x - t0.elOrigin.x) * len1 / len0)}px`
      el.style.top = `${t0.y - Math.round((t0.origin.y - t0.elOrigin.y) * len1 / len0)}px`
      el.style.height = `${Math.round(t0.elOrigin.height * len1 / len0)}px`
    }

    const pinchBackground = (t0, t1) => {
      const len0 = Math.sqrt(Math.pow(t0.origin.x - t1.origin.x, 2) + Math.pow(t0.origin.y - t1.origin.y, 2))
      const len1 = Math.sqrt(Math.pow(t0.x - t1.x, 2) + Math.pow(t0.y - t1.y, 2))
      if (el.dataset.toggleSentences !== undefined) {
        for (const [e, {x, y, fontSize}] of sentenceOrigins) {
          if (!cachedEls.has(e)) continue
          e.style.left = `${t0.x - Math.round((t0.origin.x - x) * len1 / len0)}px`
          e.style.top = `${t0.y - Math.round((t0.origin.y - y) * len1 / len0)}px`
          e.style.fontSize = `${Math.round(fontSize * len1 / len0)}px`
        }
      }
      if (el.dataset.toggleImages !== undefined) {
        for (const [e, {x, y, height}] of imageOrigins) {
          if (!cachedEls.has(e)) continue
          e.style.left = `${t0.x - Math.round((t0.origin.x - x) * len1 / len0)}px`
          e.style.top = `${t0.y - Math.round((t0.origin.y - y) * len1 / len0)}px`
          e.style.height = `${Math.round(height * len1 / len0)}px`
        }
      }
    }

    const touchMoved = () => {
      const mainTouches = touches.filter(t => t.isMain)
      if (mainTouches.length == 1) {
        const t = mainTouches[0]
        if (el.matches('.mkaps-touch-drag')) {
          el.style.left = `${t.elOrigin.x + t.x - t.origin.x}px`
          el.style.top = `${t.elOrigin.y + t.y - t.origin.y}px`
        } else if (el.id == 'background') {
          if (el.dataset.toggleSentences !== undefined) {
            for (const [e, {x, y}] of sentenceOrigins) {
              if (!cachedEls.has(e)) continue
              e.style.left = `${x + t.x - t.origin.x}px`
              e.style.top = `${y + t.y - t.origin.y}px`
            }
          }
          if (el.dataset.toggleImages !== undefined) {
            for (const [e, {x, y}] of imageOrigins) {
              if (!cachedEls.has(e)) continue
              e.style.left = `${x + t.x - t.origin.x}px`
              e.style.top = `${y + t.y - t.origin.y}px`
            }
          }
        }
      } else {
        if (el.matches('.mkaps-sentence')) pinchSentence(mainTouches[0], mainTouches[1])
        if (el.matches('.mkaps-image')) pinchImage(mainTouches[0], mainTouches[1])
        if (el.id == 'background') pinchBackground(mainTouches[0], mainTouches[1])
      }
    }

    const touchEnd = (identifier) => {
      const i = touches.findIndex(t => t.identifier == identifier)
      if (i == -1) return false
      if (el.matches('.mkaps-touch-tap') && !touches[i].moved) {
        this.pushEvent("toggle-highlight", {
          key: el.id
        })
      }
      touches.splice(i, 1)
      if (touches.length == 0) {
        el.style.cursor = "grab"
        if (el.matches('.mkaps-sentence')) {
          sentenceOrigins.set(el, {
            x: parseInt(el.style.left, 10),
            y: parseInt(el.style.top, 10),
            fontSize: parseInt(el.style.fontSize, 10)
          })
        }
        if (el.matches('.mkaps-image')) {
          imageOrigins.set(el, {
            x: parseInt(el.style.left, 10),
            y: parseInt(el.style.top, 10),
            height: parseInt(el.style.height, 10)
          })
        }
      }
      return true
    }

    const inset = (el) => {
      this.pushEvent("drag", {
        item: el.id,
        x: parseInt(el.style.left, 10),
        y: parseInt(el.style.top, 10),
        z: parseInt(el.style.zIndex, 10),
        size: getSize(el)
      })
    }

    const touchEnded = () => {
      const mainTouches = touches.filter(t => t.isMain)
      if (mainTouches.length == 2) return
      const rect = el.getBoundingClientRect()
      for (const t of touches) {
        if (t.isMain) continue
        if (!(rect.left <= t.x && t.x < rect.right)) continue
        if (!(rect.top <= t.y && t.y < rect.bottom)) continue
        t.isMain = true
        mainTouches.push(t)
        if (mainTouches.length == 2) break
      }
      if (mainTouches.length == 0) {
        if (el.matches('.mkaps-touch-drag')) inset(el)
        if (el.id == 'background') {
          Array.from(sentenceOrigins.keys()).forEach(e => {
            if (!cachedEls.has(e)) return
            sentenceOrigins.set(e, {
              x: parseInt(e.style.left, 10),
              y: parseInt(e.style.top, 10),
              fontSize: parseInt(e.style.fontSize, 10)
            })
            inset(e)
          })
          Array.from(imageOrigins.keys()).forEach(e => {
            if (!cachedEls.has(e)) return
            imageOrigins.set(e, {
              x: parseInt(e.style.left, 10),
              y: parseInt(e.style.top, 10),
              height: parseInt(e.style.height, 10)
            })
            inset(e)
          })
        }
      }
    }

    const backgroundActive = () => el.dataset.toggleSentences !== undefined || el.dataset.toggleImages !== undefined
    const backgroundActiveSentences = () => {
      const el = document.getElementById('background')
      return el.dataset.toggleSentences !== undefined && el.dataset.toggleImages === undefined
    }
    const backgroundActiveImages = () => {
      const el = document.getElementById('background')
      return el.dataset.toggleSentences === undefined && el.dataset.toggleImages !== undefined
    }

    el.addEventListener("mousedown", (e) => {
      if (Date.now() - touchended < 1000) return
      if (el.id == 'background' && !backgroundActive()) return
      if (el.matches('.mkaps-image') && backgroundActiveSentences()) return
      if (el.matches('.mkaps-sentence') && backgroundActiveImages()) return
      touchStart('mouse', e)
    })
    el.addEventListener("touchstart", (e) => {
      for (const touch of e.changedTouches) {
        if (!el.contains(touch.target)) continue
        if (el.id == 'background' && !backgroundActive()) continue
        if (el.matches('.mkaps-image') && backgroundActiveSentences()) continue
        if (el.matches('.mkaps-sentence') && backgroundActiveImages()) continue
        touchStart(touch.identifier, touch)
      }
    }, { passive: false })

    window.addEventListener("mousemove", (e) => {
      if (touchMove('mouse', e)) touchMoved()
    })
    window.addEventListener("touchmove", (e) => {
      let mainMoved = false
      for (const touch of e.changedTouches) {
        if (!el.contains(touch.target)) continue
        if (!touchMove(touch.identifier, touch)) continue
        e.preventDefault()
        mainMoved = true
      }
      if (mainMoved) touchMoved()
    }, { passive: false })

    window.addEventListener("mouseup", (e) => {
      if (touchEnd('mouse')) touchEnded()
    })
    window.addEventListener("touchend", (e) => {
      let ended = false
      for (const touch of e.changedTouches) {
        if (!el.contains(touch.target)) continue
        if (!touchEnd(touch.identifier)) continue
        ended = true
        touchended = Date.now()
      }
      if (ended) touchEnded()
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
    this.el.addEventListener("click", () => {
      if (document.fullscreenElement) {
        document.exitFullscreen?.();
      } else {
        document.documentElement.requestFullscreen?.();
      }
    });
  }
}

export default Hooks
