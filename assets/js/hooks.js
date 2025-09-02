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
      const allZ = Array.from(document.querySelectorAll('.mkaps-draggable')).map(e => e.style.zIndex);
      el.style.zIndex = Math.max(...allZ) + 1
      e.preventDefault()
    }

    const doDrag = (e) => {
      if (!isDragging) return
      const point = e.touches ? e.touches[0] : e
      el.style.left = point.clientX - offset.x + "px"
      el.style.top = point.clientY - offset.y + "px"
    }

    const stopDrag = () => {
      if (!isDragging) return
      isDragging = false
      el.style.cursor = "grab"
      this.pushEvent("drag", {
        object: el.id,
        x: parseInt(el.style.left, 10),
        y: parseInt(el.style.top, 10),
        z: parseInt(el.style.zIndex, 10)
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

export default Hooks
