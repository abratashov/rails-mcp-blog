import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    if (this.element.scrollHeight > this.element.clientHeight) {
      this.element.scrollTop = this.element.scrollHeight
    }

    window.scrollTo(0, document.body.scrollHeight)
  }
}
