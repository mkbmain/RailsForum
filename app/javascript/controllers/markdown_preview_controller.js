import { Controller } from "@hotwired/stimulus"
import { marked } from "marked"

const ACTIVE_TAB   = "px-4 py-2 text-sm font-medium text-blue-600 border-b-2 border-blue-600 dark:text-blue-400 dark:border-blue-400"
const INACTIVE_TAB = "px-4 py-2 text-sm text-gray-500 hover:text-gray-700 dark:text-stone-400 dark:hover:text-stone-200"

export default class extends Controller {
  static targets = ["textarea", "preview", "writeTab", "previewTab"]

  showWrite() {
    this.textareaTarget.classList.remove("hidden")
    this.previewTarget.classList.add("hidden")
    this.writeTabTarget.className   = ACTIVE_TAB
    this.previewTabTarget.className = INACTIVE_TAB
  }

  showPreview() {
    const text = this.textareaTarget.value
    this.previewTarget.style.minHeight = this.textareaTarget.offsetHeight + "px"

    if (text.trim() === "") {
      this.previewTarget.innerHTML = '<p class="text-gray-400 italic">Nothing to preview.</p>'
    } else {
      this.previewTarget.innerHTML = marked(text)
    }

    this.textareaTarget.classList.add("hidden")
    this.previewTarget.classList.remove("hidden")
    this.writeTabTarget.className   = INACTIVE_TAB
    this.previewTabTarget.className = ACTIVE_TAB
  }
}
