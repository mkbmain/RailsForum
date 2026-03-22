import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["textarea"]
  static values  = { users: Array }

  connect() {
    this._dropdown  = null
    this._matches   = []
    this._index     = -1
    this._onInput   = this._handleInput.bind(this)
    this._onKeydown = this._handleKeydown.bind(this)
    this._onBlur    = this._handleBlur.bind(this)
    this.textareaTarget.addEventListener("input",   this._onInput)
    this.textareaTarget.addEventListener("keydown", this._onKeydown)
    this.textareaTarget.addEventListener("blur",    this._onBlur)
  }

  disconnect() {
    this.textareaTarget.removeEventListener("input",   this._onInput)
    this.textareaTarget.removeEventListener("keydown", this._onKeydown)
    this.textareaTarget.removeEventListener("blur",    this._onBlur)
    this._removeDropdown()
  }

  // ── private ──────────────────────────────────────────────────────────────

  _handleInput() {
    const fragment = this._currentFragment()
    if (fragment === null) { this._removeDropdown(); return }
    this._matches = this._filter(fragment)
    this._matches.length ? this._showDropdown() : this._removeDropdown()
  }

  _handleKeydown(event) {
    if (!this._dropdown) return
    if (event.key === "ArrowDown") {
      event.preventDefault()
      this._index = Math.min(this._index + 1, this._matches.length - 1)
      this._updateHighlight()
    } else if (event.key === "ArrowUp") {
      event.preventDefault()
      this._index = Math.max(this._index - 1, 0)
      this._updateHighlight()
    } else if (event.key === "Enter") {
      if (this._index >= 0) {
        event.preventDefault()
        this._selectMatch(this._matches[this._index])
      }
    } else if (event.key === "Tab") {
      if (this._index >= 0) {
        event.preventDefault()
        this._selectMatch(this._matches[this._index])
      }
    } else if (event.key === "Escape") {
      this._removeDropdown()
    }
  }

  _handleBlur() {
    // Delay to let a click on a dropdown item register first
    setTimeout(() => this._removeDropdown(), 150)
  }

  _currentFragment() {
    const ta    = this.textareaTarget
    const value = ta.value
    const pos   = ta.selectionStart
    const before = value.slice(0, pos)
    const match  = before.match(/@(\w*)$/)
    return match ? match[1] : null
  }

  _filter(fragment) {
    if (fragment === "") return this.usersValue.slice(0, 6)
    const lower = fragment.toLowerCase()
    return this.usersValue
      .filter(u => u.token.toLowerCase().includes(lower))
      .slice(0, 6)
  }

  _showDropdown() {
    this._removeDropdown()
    this._index = -1

    const rect = this.textareaTarget.getBoundingClientRect()
    const ul   = document.createElement("ul")
    ul.setAttribute("role", "listbox")
    ul.style.cssText = [
      "position:fixed",
      `top:${rect.bottom + 2}px`,
      `left:${rect.left}px`,
      "z-index:9999",
      "min-width:160px",
      "max-width:300px"
    ].join(";")
    ul.className = [
      "bg-white dark:bg-stone-800",
      "border border-gray-200 dark:border-stone-600",
      "rounded-md shadow-lg",
      "py-1",
      "text-sm"
    ].join(" ")

    this._matches.forEach((entry, i) => {
      const li = document.createElement("li")
      li.setAttribute("role", "option")
      li.dataset.index = i
      li.textContent   = entry.display
      li.className     = "px-3 py-1.5 cursor-pointer text-stone-800 dark:text-stone-100 hover:bg-blue-50 dark:hover:bg-stone-700"
      li.addEventListener("mousedown", (e) => {
        e.preventDefault()  // prevent textarea blur before click completes
        this._selectMatch(entry)
      })
      ul.appendChild(li)
    })

    document.body.appendChild(ul)
    this._dropdown = ul
  }

  _updateHighlight() {
    if (!this._dropdown) return
    Array.from(this._dropdown.children).forEach((li, i) => {
      if (i === this._index) {
        li.classList.add("bg-blue-100", "dark:bg-stone-600")
      } else {
        li.classList.remove("bg-blue-100", "dark:bg-stone-600")
      }
    })
  }

  _selectMatch(entry) {
    const ta    = this.textareaTarget
    const pos   = ta.selectionStart
    const value = ta.value
    const before  = value.slice(0, pos)
    const after   = value.slice(pos)
    const replaced = before.replace(/@(\w*)$/, `@${entry.token} `)
    ta.value = replaced + after
    const newPos = replaced.length
    ta.setSelectionRange(newPos, newPos)
    ta.focus()
    this._removeDropdown()
  }

  _removeDropdown() {
    if (this._dropdown) {
      this._dropdown.remove()
      this._dropdown = null
    }
    this._matches = []
    this._index   = -1
  }
}
