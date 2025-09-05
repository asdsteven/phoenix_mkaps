let Hooks = {}

let touches = new Map()

Hooks.Draggable = {
  mounted() {
    let el = this.el
    let offset = { x: 0, y: 0 }
    let origin = { x: 0, y: 0 }
    let isDragging = 0
    let touchended = false

    const startDrag = (point) => {
      origin.x = point.clientX
      origin.y = point.clientY
      offset.x = point.clientX - parseInt(el.style.left, 10)
      offset.y = point.clientY - parseInt(el.style.top, 10)
      const allZ = Array.from(document.querySelectorAll('.mkaps-draggable')).map(e => e.style.zIndex);
      el.style.zIndex = Math.max(...allZ) + 1
    }

    const doDrag = (point) => {
      el.style.cursor = "grabbing"
      el.style.left = point.clientX - offset.x + "px"
      el.style.top = point.clientY - offset.y + "px"
    }

    const toggleGrapheme = (key) => {
      this.pushEvent("toggle-grapheme", {
        key: key
      })
    }

    const stopDrag = () => {
      el.style.cursor = "grab"
      this.pushEvent("drag", {
        item: el.id,
        x: parseInt(el.style.left, 10),
        y: parseInt(el.style.top, 10),
        z: parseInt(el.style.zIndex, 10)
      })
    }

    el.style.cursor = "grab"

    el.addEventListener("mousedown", (e) => {
      if (touchended) return
      if (isDragging) return
      isDragging = 1
      startDrag(e)
    })
    el.addEventListener("touchstart", (e) => {
      if (isDragging) return
      for (const touch of e.changedTouches) {
        if (touches.has(touch.identifier)) continue
        if (touch.target.closest('.mkaps-draggable') !== el) continue
        e.preventDefault()
        isDragging = 11
        touches.set(touch.identifier, el)
        startDrag(touch)
        break
      }
    }, { passive: false })

    window.addEventListener("mousemove", (e) => {
      if (![1, 2].includes(isDragging)) return
      if (isDragging == 1 && Math.abs(e.clientX - origin.x) < 10 && Math.abs(e.clientY - origin.y) < 10) return
      isDragging = 2
      doDrag(e)
    })
    window.addEventListener("touchmove", (e) => {
      if (![11, 12].includes(isDragging)) return
      for (const touch of e.changedTouches) {
        if (touches.get(touch.identifier) !== el) continue
        if (isDragging == 11 && Math.abs(touch.clientX - origin.x) < 10 && Math.abs(touch.clientY - origin.y) < 10) return
        e.preventDefault()
        isDragging = 12
        doDrag(touch)
        break
      }
    }, { passive: false })

    window.addEventListener("mouseup", (e) => {
      if (![1, 2].includes(isDragging)) return
      if (isDragging == 1) {
        if (e.target.dataset.key) toggleGrapheme(e.target.dataset.key)
      } else {
        stopDrag()
      }
      isDragging = 0
    })
    window.addEventListener("touchend", (e) => {
      if (![11, 12].includes(isDragging)) return
      for (const touch of e.changedTouches) {
        if (touches.get(touch.identifier) !== el) continue
        if (isDragging == 11) {
          toggleGrapheme(e.target.dataset.key)
        } else {
          stopDrag()
        }
        isDragging = 0
        touches.delete(touch.identifier)
        touchended = true
        break
      }
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
