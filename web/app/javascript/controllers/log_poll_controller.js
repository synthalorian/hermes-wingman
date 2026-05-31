import { Controller } from "@hotwired/stimulus"

// Polls the live logs endpoint and refreshes the Turbo Stream frame.
export default class extends Controller {
  static values = {
    url: String,
    interval: { type: Number, default: 5000 }
  }

  connect() {
    this.poll()
    this.timer = setInterval(() => this.poll(), this.intervalValue)
  }

  disconnect() {
    if (this.timer) clearInterval(this.timer)
  }

  poll() {
    fetch(this.urlValue, {
      headers: { "Accept": "text/vnd.turbo-stream.html" }
    }).catch(() => {
      // Silently ignore network errors; the next poll will retry.
    })
  }
}
