import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["toggleButton"]

  connect() {
    if (!localStorage.getItem('theme')) {
      this._mediaQuery = window.matchMedia('(prefers-color-scheme: dark)')
      this._listener = (e) => {
        document.documentElement.classList.toggle('dark', e.matches)
        this._updateLabel()
      }
      this._mediaQuery.addEventListener('change', this._listener)
    }
    this._updateLabel()
  }

  disconnect() {
    if (this._mediaQuery && this._listener) {
      this._mediaQuery.removeEventListener('change', this._listener)
    }
  }

  toggle() {
    const isDark = document.documentElement.classList.toggle('dark')
    localStorage.setItem('theme', isDark ? 'dark' : 'light')
    if (this._mediaQuery && this._listener) {
      this._mediaQuery.removeEventListener('change', this._listener)
      this._mediaQuery = null
      this._listener = null
    }
    this._updateLabel()
  }

  _updateLabel() {
    if (this.hasToggleButtonTarget) {
      const isDark = document.documentElement.classList.contains('dark')
      this.toggleButtonTarget.setAttribute('aria-label', isDark ? 'Switch to light mode' : 'Switch to dark mode')
    }
  }
}
