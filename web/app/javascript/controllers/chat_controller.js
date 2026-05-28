import { Controller } from "@hotwired/stimulus"

// Chat controller — manages SSE streaming chat with the Hermes agent.
// Renders user and AI message bubbles, handles session switching,
// and connects to the Rust backend SSE stream for real-time responses.
export default class extends Controller {
  static targets = ["messages", "input", "sendButton", "sessionTabs", "emptyState", "container"]

  connect() {
    this.currentSessionId = null
    this.eventSource = null
    this.streaming = false
    this.accumulator = ""
    this.currentAiBubble = null

    // Auto-resize textarea on input
    this.inputTarget.addEventListener("input", () => this._autoResizeTextarea())

    // Enable send button when there's text
    this.inputTarget.addEventListener("input", () => this._updateSendButton())

    // Scroll to bottom on connect
    this.scrollToBottom()
  }

  disconnect() {
    this._closeStream()
  }

  // ── Actions ──────────────────────────────────────────────────────────

  // send(event) — sends the user message and starts streaming
  send(event) {
    event.preventDefault()

    const text = this.inputTarget.value.trim()
    if (!text || this.streaming) return

    // Append user message
    this.appendMessage(text, true)

    // Clear input
    this.inputTarget.value = ""
    this._autoResizeTextarea()
    this._updateSendButton()

    // Hide empty state
    this._hideEmptyState()

    // Send to backend
    this._startStreaming(text)
  }

  // handleKeydown — send on Enter (without Shift), newline on Shift+Enter
  handleKeydown(event) {
    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault()
      this.send(event)
    }
  }

  // newSession — clear messages and reset session
  newSession(event) {
    event.preventDefault()
    this._closeStream()
    this.currentSessionId = null
    this.messagesTarget.innerHTML = ""
    this.accumulator = ""
    this.currentAiBubble = null
    this.streaming = false

    // Re-show empty state
    this._showEmptyState()

    // Deselect all session tabs
    this.sessionTabsTarget.querySelectorAll("button[data-session-id]").forEach(btn => {
      btn.style.borderColor = "var(--border-light)"
      btn.style.color = "var(--text-secondary)"
    })
  }

  // switchSession — load a different session's messages
  switchSession(event) {
    const sessionId = event.currentTarget.dataset.sessionId
    if (!sessionId) return

    this._closeStream()
    this.currentSessionId = sessionId
    this.messagesTarget.innerHTML = ""
    this.accumulator = ""
    this.currentAiBubble = null
    this.streaming = false

    // Highlight active tab
    this.sessionTabsTarget.querySelectorAll("button[data-session-id]").forEach(btn => {
      const isActive = btn.dataset.sessionId === sessionId
      btn.style.borderColor = isActive ? "var(--accent-tertiary)" : "var(--border-light)"
      btn.style.color = isActive ? "var(--accent-tertiary)" : "var(--text-secondary)"
    })

    // TODO: In a future iteration, fetch session history from backend
    // For now, show a placeholder message
    this.appendMessage("Resumed session. Continue your conversation below.", false)

    this._hideEmptyState()
  }

  // ── Streaming ────────────────────────────────────────────────────────

  // connectStream(url) — opens an EventSource to the Rust backend SSE endpoint
  connectStream(url) {
    this._closeStream()

    this.eventSource = new EventSource(url)
    this.streaming = true
    this.accumulator = ""

    // Start the AI bubble (empty, will be filled incrementally)
    this.currentAiBubble = this.appendMessage("", false)

    this.eventSource.addEventListener("data", (event) => {
      this.handleData(event.data)
    })

    this.eventSource.addEventListener("message", (event) => {
      // Fallback — some SSE implementations use the default message event
      this.handleData(event.data)
    })

    this.eventSource.addEventListener("done", () => {
      this.handleDone()
    })

    this.eventSource.addEventListener("error", () => {
      // EventSource auto-reconnects on transient errors.
      // If readyState is CLOSED (2), the stream ended definitively.
      if (this.eventSource && this.eventSource.readyState === EventSource.CLOSED) {
        this.handleDone()
      }
    })

    // Timeout safety — if the stream doesn't send any data for 60s, close it
    this._streamTimeout = setTimeout(() => {
      if (this.streaming) {
        this.handleDone()
        this.appendMessage("[Stream timed out after 60s]", false)
      }
    }, 60000)
  }

  // handleData(data) — parses SSE data and appends to the current AI bubble
  handleData(data) {
    if (!data || data === "[DONE]") {
      this.handleDone()
      return
    }

    try {
      // Try parsing as JSON (expected: { content: "..." })
      const parsed = JSON.parse(data)
      const content = parsed.content || parsed.text || parsed.message || ""
      if (content) {
        this.accumulator += content
        this._updateAiBubble(this.accumulator)
        this.scrollToBottom()
      }
    } catch {
      // Plain text fallback — append raw data
      this.accumulator += data
      this._updateAiBubble(this.accumulator)
      this.scrollToBottom()
    }
  }

  // handleDone() — closes the stream and finalizes the current AI message
  handleDone() {
    if (!this.streaming) return

    this._closeStream()

    // Finalize the bubble (no more updates)
    if (this.currentAiBubble) {
      this.currentAiBubble.dataset.streaming = "false"
      // Remove the blinking cursor indicator if present
      this.currentAiBubble.style.borderRight = "none"
    }

    this.streaming = false
    this.currentAiBubble = null
    this.inputTarget.focus()
  }

  // ── DOM ──────────────────────────────────────────────────────────────

  // appendMessage(text, isUser) — creates a chat bubble and appends it
  appendMessage(text, isUser) {
    const bubble = document.createElement("div")
    bubble.className = isUser ? "chat-bubble-user" : "chat-bubble-ai"
    bubble.dataset.streaming = "false"

    // Style
    const baseStyle = `
      max-width: 80%;
      padding: 10px 14px;
      border-radius: var(--radius-lg);
      font-size: 13px;
      line-height: 1.6;
      word-wrap: break-word;
      white-space: pre-wrap;
      animation: chatBubbleIn 0.2s ease-out;
    `

    if (isUser) {
      bubble.style.cssText = baseStyle + `
        align-self: flex-end;
        background: var(--accent-tertiary);
        color: var(--bg-primary);
        border-bottom-right-radius: 4px;
      `
      bubble.textContent = text
    } else {
      bubble.style.cssText = baseStyle + `
        align-self: flex-start;
        background: var(--bg-surface);
        border: 1px solid var(--border-light);
        color: var(--text-primary);
        border-bottom-left-radius: 4px;
      `

      if (text) {
        bubble.textContent = text
      } else {
        // Empty AI bubble — add a blinking cursor for streaming
        bubble.style.borderRight = "2px solid var(--accent-tertiary)"
        bubble.style.animation = "blink 0.8s step-end infinite"
        bubble.innerHTML = "&nbsp;"
      }

      // Add small "AI" label
      const label = document.createElement("div")
      label.style.cssText = `
        font-size: 8px;
        font-family: var(--font-mono);
        color: var(--text-muted);
        letter-spacing: 0.5px;
        margin-bottom: 4px;
      `
      label.textContent = "HERMES"
      bubble.prepend(label)
    }

    this.messagesTarget.appendChild(bubble)
    this.scrollToBottom()
    return bubble
  }

  scrollToBottom() {
    this.messagesTarget.scrollTop = this.messagesTarget.scrollHeight
  }

  // ── Private ──────────────────────────────────────────────────────────

  _startStreaming(text) {
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

    fetch("/chat/send_message", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": csrfToken
      },
      body: JSON.stringify({
        message: text,
        session_id: this.currentSessionId
      })
    })
      .then(response => {
        if (!response.ok) {
          return response.json().then(err => { throw new Error(err.error || "Request failed") })
        }
        return response.json()
      })
      .then(data => {
        if (data.stream_url) {
          this.connectStream(data.stream_url)
        } else if (data.error) {
          throw new Error(data.error)
        }
      })
      .catch(error => {
        this._closeStream()
        this.streaming = false
        this.appendMessage(`Error: ${error.message}`, false)
      })
  }

  _closeStream() {
    if (this.eventSource) {
      this.eventSource.close()
      this.eventSource = null
    }
    if (this._streamTimeout) {
      clearTimeout(this._streamTimeout)
      this._streamTimeout = null
    }
    // Reset streaming state on AI bubble
    if (this.currentAiBubble) {
      this.currentAiBubble.style.borderRight = "none"
      this.currentAiBubble.style.animation = ""
    }
  }

  _updateAiBubble(text) {
    if (!this.currentAiBubble) return

    // Clear inner HTML but keep the label
    const label = this.currentAiBubble.querySelector("div")
    this.currentAiBubble.innerHTML = ""
    if (label) {
      this.currentAiBubble.appendChild(label)
    }

    // Add text content node
    const textNode = document.createTextNode(text)
    this.currentAiBubble.appendChild(textNode)

    // Keep blinking cursor
    this.currentAiBubble.style.borderRight = "2px solid var(--accent-tertiary)"
    this.currentAiBubble.style.animation = "blink 0.8s step-end infinite"
  }

  _autoResizeTextarea() {
    const el = this.inputTarget
    el.style.height = "auto"
    el.style.height = Math.min(el.scrollHeight, 120) + "px"
  }

  _updateSendButton() {
    const hasText = this.inputTarget.value.trim().length > 0
    this.sendButtonTarget.disabled = !hasText || this.streaming
    this.sendButtonTarget.style.opacity = this.sendButtonTarget.disabled ? "0.4" : "1"
  }

  _hideEmptyState() {
    const empty = this.emptyStateTarget
    if (empty) empty.style.display = "none"
  }

  _showEmptyState() {
    const empty = this.emptyStateTarget
    if (empty) empty.style.display = ""
  }
}

// Inject keyframe animations once
if (!document.getElementById("chat-animations")) {
  const style = document.createElement("style")
  style.id = "chat-animations"
  style.textContent = `
    @keyframes chatBubbleIn {
      from { opacity: 0; transform: translateY(8px); }
      to   { opacity: 1; transform: translateY(0); }
    }
    @keyframes blink {
      50% { border-color: transparent; }
    }
  `
  document.head.appendChild(style)
}