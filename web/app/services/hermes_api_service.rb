# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

# Service object that wraps all communication to the Rust Hermes Wingman backend.
# Every method maps 1:1 to a Rust endpoint on port 9120.
# The Rails webapp never calls `hermes` directly — this service is the sole
# integration point.
class HermesApiService
  BASE_URL = ENV.fetch("HERMES_BACKEND_URL", "http://127.0.0.1:9120")
  TIMEOUT = ENV.fetch("HERMES_TIMEOUT", "10").to_i

  class BackendError < StandardError; end

  # ── Health & Status ────────────────────────────────────────────────────

  def self.health
    get("/health")
  end

  def self.status
    health
  end

  def self.hermes_version
    get("/hermes/version")
  end

  # ── Chat ───────────────────────────────────────────────────────────────

  # Non-streaming chat — returns full response text
  def self.chat(message, session_id: nil)
    body = { message: message }
    body[:session_id] = session_id if session_id
    post("/chat", body)
  end

  # Streaming chat URL — used by the browser for EventSource
  def self.chat_stream_url(message, session_id: nil)
    params = { message: message }
    params[:session_id] = session_id if session_id
    "#{BASE_URL}/chat/stream?#{URI.encode_www_form(params)}"
  end

  # ── Sessions ───────────────────────────────────────────────────────────

  def self.list_sessions(limit: 20)
    get("/sessions", limit: limit)
  end

  def self.get_session(id)
    get("/sessions/#{id}")
  end

  def self.delete_session(id)
    delete_request("/sessions/#{id}")
  end

  # ── Models ─────────────────────────────────────────────────────────────

  def self.list_models
    get("/models")
  end

  def self.switch_model(model_name)
    post("/models/switch", { model: model_name })
  end

  def self.probe_model(model_name)
    post("/models/probe", { model: model_name })
  end

  # ── Config ─────────────────────────────────────────────────────────────

  def self.get_config
    get("/config")
  end

  def self.write_config(content)
    post("/config/write", { content: content })
  end

  def self.update_config(updates)
    post("/config/update", { updates: updates })
  end

  # ── Logs ───────────────────────────────────────────────────────────────

  def self.get_logs(lines: 50, level: "all")
    get("/logs", lines: lines, level: level)
  end

  # ── Cron ───────────────────────────────────────────────────────────────

  def self.list_cron_jobs
    get("/cron")
  end

  # ── Gateway ────────────────────────────────────────────────────────────

  def self.get_gateway_status
    get("/gateway")
  end

  def self.toggle_gateway(action)
    post("/gateway/toggle", { action: action })
  end

  # ── Providers ──────────────────────────────────────────────────────────

  def self.list_providers
    get("/providers")
  end

  def self.probe_provider(provider_name, api_key: nil, base_url: nil)
    body = { name: provider_name }
    body[:api_key] = api_key if api_key
    body[:base_url] = base_url if base_url
    post("/setup/probe-provider", body)
  end

  # ── Setup ──────────────────────────────────────────────────────────────

  def self.detect_setup
    get("/setup/detect")
  end

  def self.install_hermes(method: "pip")
    post("/setup/install", { method: method })
  end

  def self.auto_configure
    post("/setup/auto-configure", {})
  end

  # ── Hermes Management ──────────────────────────────────────────────────

  def self.hermes_update
    post("/hermes/update", {})
  end

  def self.list_skills
    get("/hermes/skills")
  end

  # ── Runners ────────────────────────────────────────────────────────────

  def self.run_hermes_command(args)
    post("/hermes/command", { args: args })
  end

  # ── Skills ────────────────────────────────────────────────────────────

  def self.toggle_skill(name, action = "toggle")
    post("/hermes/skills/#{name}/toggle", { action: action })
  end

  # ── Memory ────────────────────────────────────────────────────────────

  def self.list_memory
    get("/memory")
  end

  def self.get_memory(id)
    get("/memory/#{id}")
  end

  def self.delete_memory(id)
    delete_request("/memory/#{id}")
  end

  def self.search_memory(query)
    post("/memory/search", { query: query })
  end

  # ── Files ─────────────────────────────────────────────────────────────

  def self.list_files(path = "")
    get("/files/list", path: path)
  end

  def self.read_file(path)
    get("/files/read", path: path)
  end

  def self.write_file(path, content)
    put_request("/files/write", { path: path, content: content })
  end

  # ── File Operations ──────────────────────────────────────────────────

  def self.get_file_info(path)
    get("/files/info", path: path)
  end

  def self.delete_file(path)
    post("/files/delete", { path: path })
  end

  def self.rename_file(path, new_name)
    post("/files/rename", { path: path, new_name: new_name })
  end

  def self.create_directory(path, name)
    post("/files/mkdir", { path: path, name: name })
  end

  # ── Auth / Providers ─────────────────────────────────────────────────

  def self.auth_status
    get("/auth/status")
  end

  def self.login_oauth(provider)
    post("/auth/login/#{provider}", {})
  end

  def self.login_api_key(provider, api_key)
    post("/auth/api-key", { provider: provider, api_key: api_key })
  end

  def self.logout_provider(provider)
    post("/auth/logout/#{provider}", {})
  end

  # ── Gateway Platforms ────────────────────────────────────────────────

  def self.get_gateway_platforms
    get("/gateway/platforms")
  end

  def self.configure_gateway_platform(platform, vars)
    post("/gateway/configure/#{platform}", { vars: vars })
  end

  def self.gateway_service_action(action)
    post("/gateway/service/#{action}", {})
  end

  # ── Fallback Providers ───────────────────────────────────────────────

  def self.get_fallback_chain
    get("/cli/fallback")
  end

  def self.add_fallback(provider, model)
    post("/cli/fallback/add", { provider: provider, model: model })
  end

  def self.clear_fallback
    post("/cli/fallback/clear", {})
  end

  # ── CLI Tools ────────────────────────────────────────────────────────

  def self.list_webhooks
    get("/cli/webhooks")
  end

  def self.list_hooks
    get("/cli/hooks")
  end

  def self.list_plugins
    get("/cli/plugins")
  end

  def self.curator_status
    get("/cli/curator")
  end

  def self.list_mcp_servers
    get("/cli/mcp")
  end

  def self.run_doctor
    get("/cli/doctor")
  end

  def self.run_security_audit
    get("/cli/security")
  end

  def self.get_dump
    get("/cli/dump")
  end

  def self.create_debug_report
    get("/cli/debug")
  end

  def self.create_backup
    post("/cli/backup", {})
  end

  def self.get_checkpoints
    get("/cli/checkpoints")
  end

  def self.get_proxy_status
    get("/cli/proxy")
  end

  def self.get_secrets_status
    get("/cli/secrets")
  end

  def self.list_pairing_users
    get("/cli/pairing")
  end

  def self.get_insights
    get("/cli/insights")
  end

  private

  def self.request(method, path, body = nil)
    uri = URI("#{BASE_URL}#{path}")

    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = 5
    http.read_timeout = TIMEOUT
    http.continue_timeout = nil

    case method
    when :get
      uri.query = URI.encode_www_form(body) if body&.any?
      response = Net::HTTP.get_response(uri)
    when :post
      req = Net::HTTP::Post.new(uri.request_uri)
      req["Content-Type"] = "application/json"
      req["Accept"] = "application/json"
      req.body = (body || {}).to_json
      response = http.start { |conn| conn.request(req) }
    when :put
      req = Net::HTTP::Put.new(uri.request_uri)
      req["Content-Type"] = "application/json"
      req["Accept"] = "application/json"
      req.body = (body || {}).to_json
      response = http.start { |conn| conn.request(req) }
    when :delete
      req = Net::HTTP::Delete.new(uri.request_uri)
      req["Accept"] = "application/json"
      response = http.start { |conn| conn.request(req) }
    else
      raise ArgumentError, "Unsupported HTTP method: #{method}"
    end

    parse_response(response, path)
  rescue EOFError, Errno::ECONNRESET, Errno::EPIPE, Timeout::Error, Net::OpenTimeout, Net::ReadTimeout => e
    raise BackendError, "Connection error to backend at #{path}: #{e.class}"
  end

  def self.get(path, params = {})
    request(:get, path, params)
  end

  def self.post(path, body = {})
    request(:post, path, body)
  end

  def self.put_request(path, body = {})
    request(:put, path, body)
  end

  def self.delete_request(path)
    request(:delete, path)
  end

  def self.parse_response(response, path)
    case response
    when Net::HTTPOK
      body = response.body
      body.present? ? JSON.parse(body) : { "status" => "ok" }
    when Net::HTTPNotFound
      raise BackendError, "Endpoint not found: #{path}"
    else
      raise BackendError, "Backend error (#{response.code}): #{response.body&.truncate(200)}"
    end
  rescue JSON::ParserError => e
    raise BackendError, "Invalid JSON from backend at #{path}: #{e.message}"
  rescue Net::TimeoutError
    raise BackendError, "Backend timeout at #{path} (backend may be down)"
  rescue Errno::ECONNREFUSED
    raise BackendError, "Cannot connect to backend at #{BASE_URL}. Is Hermes Wingman running?"
  end
end
