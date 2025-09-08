let Hooks = {}

Hooks.Touchable = {
  mounted() {
    const el = this.el
    const touches = []
    let touchended = 0

    const inset = () => {
      const rect = el.getBoundingClientRect()
      const lip = 10
      if (rect.right < lip) el.style.left = `${lip - rect.width}px`
      if (rect.left > 1280 - lip) el.style.left = `${1280 - lip}px`
      if (rect.bottom < lip) el.style.top = `${lip - rect.height}px`
      if (rect.top > 720 - lip) el.style.top = `${720 - lip}px`
      this.pushEvent("drag", {
        item: el.id,
        x: parseInt(el.style.left, 10),
        y: parseInt(el.style.top, 10),
        z: parseInt(el.style.zIndex, 10)
      })
    }

    const touchStart = (identifier, point) => {
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
          y: parseInt(el.style.top, 10)
        },
        x: point.clientX,
        y: point.clientY
      })
      el.style.cursor = "grabbing"
      this.pushEvent("drag", {
        item: el.id,
        x: parseInt(el.style.left, 10),
        y: parseInt(el.style.top, 10),
        z: parseInt(el.style.zIndex, 10)
      })
    }

    const touchMove = (identifier, point) => {
      const t = touches.find(t => t.identifier == identifier)
      if (!t) return false
      t.x = point.clientX
      t.y = point.clientY
      t.moved ||= Math.abs(t.x - t.origin.x) >= 10
      t.moved ||= Math.abs(t.y - t.origin.y) >= 10
      return t.moved && t.isMain
    }

    const pinch = (t0, t1) => {
    }

    const touchMoved = () => {
      const mainTouches = touches.filter(t => t.isMain)
      if (mainTouches.length == 1) {
        if (el.matches('.mkaps-touch-drag')) {
          const t = mainTouches[0]
          el.style.left = `${t.elOrigin.x + t.x - t.origin.x}px`
          el.style.top = `${t.elOrigin.y + t.y - t.origin.y}px`
          touches.forEach(t => t.moved = true)
          const allZ = Array.from(document.querySelectorAll('.mkaps-touch-drag')).map(e => e.style.zIndex);
          el.style.zIndex = Math.max(...allZ) + 1
        }
      } else {
        if (el.matches('.mkaps-touch-drag')) {
          pinch(mainTouches[0], mainTouches[1])
        }
      }
    }

    const touchEnd = (identifier) => {
      const i = touches.findIndex(t => t.identifier == identifier)
      if (i == -1) return
      if (el.matches('.mkaps-touch-tap') && !touches[i].moved) {
        this.pushEvent("toggle-highlight", {
          key: el.id
        })
      }
      touches.splice(i, 1)
      if (touches.length == 0) el.style.cursor = "grab"
    }

    const touchEnded = () => {
      const mainTouches = touches.filter(t => t.isMain)
      if (mainTouches.length == 2) return
      if (mainTouches.length == 0 && el.matches('.mkaps-touch-drag')) inset()
      const rect = el.getBoundingClientRect()
      for (const t of touches) {
        if (t.isMain) continue
        if (!(rect.left <= t.x && t.x < rect.right)) continue
        if (!(rect.top <= t.y && t.y < rect.bottom)) continue
        t.isMain = true
        mainTouches.push(t)
        if (mainTouches.length == 2) break
      }
    }

    el.style.cursor = "grab"

    el.addEventListener("mousedown", (e) => {
      if (Date.now() - touchended < 1000) return
      touchStart('mouse', e)
    })
    el.addEventListener("touchstart", (e) => {
      for (const touch of e.changedTouches) {
        if (!el.contains(touch.target)) continue
        e.preventDefault()
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
        e.preventDefault()
        mainMoved ||= touchMove(touch.identifier, touch)
      }
      if (mainMoved) touchMoved()
    }, { passive: false })

    window.addEventListener("mouseup", (e) => {
      touchEnd('mouse')
      touchEnded()
    })
    window.addEventListener("touchend", (e) => {
      for (const touch of e.changedTouches) {
        if (!el.contains(touch.target)) continue
        touchEnd(touch.identifier)
        touchended = Date.now()
      }
      touchEnded()
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
