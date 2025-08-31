let Hooks = {}

Hooks.Draggable = {
  mounted() {
    let el = this.el
    let offset = { x: 0, y: 0 }
    let isDragging = false

    const startDrag = (e) => {
      isDragging = true
      const point = e.touches ? e.touches[0] : e
      offset.x = point.clientX - parseInt(el.style.left, 10)
      offset.y = point.clientY - parseInt(el.style.top, 10)
      el.style.cursor = "grabbing"
    }

    const doDrag = (e) => {
      if (!isDragging) return
      const point = e.touches ? e.touches[0] : e
      el.style.left = point.clientX - offset.x + "px"
      el.style.top = point.clientY - offset.y + "px"
    }

    const stopDrag = () => {
      isDragging = false
      el.style.cursor = "grab"
      this.pushEvent("update_position", {
        x: parseInt(el.style.left, 10),
        y: parseInt(el.style.top, 10)
      })
    }

    el.style.cursor = "grab"

    el.addEventListener("mousedown", startDrag)
    el.addEventListener("touchstart", startDrag)

    window.addEventListener("mousemove", doDrag)
    window.addEventListener("touchmove", doDrag)

    window.addEventListener("mouseup", stopDrag)
    window.addEventListener("touchend", stopDrag)
  }
}

export default Hooks
