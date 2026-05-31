# frozen_string_literal: true

# JSON endpoints for Stimulus controllers — proxies to Rust backend via HermesApiService.
# Error handling is centralized in ApplicationController#rescue_from.
class ApiController < ApplicationController
  def health         = render(json: HermesApiService.health)
  def status         = render(json: HermesApiService.health)
  def models         = render(json: HermesApiService.list_models)
  def sessions       = render(json: HermesApiService.list_sessions)
  def logs           = render(json: HermesApiService.get_logs)
  def cron           = render(json: HermesApiService.list_cron_jobs)
  def gateway        = render(json: HermesApiService.get_gateway_status)
  def gateway_platforms = render(json: HermesApiService.get_gateway_platforms)
  def providers      = render(json: HermesApiService.list_providers)
  def auth_status    = render(json: HermesApiService.auth_status)
  def skills         = render(json: HermesApiService.list_skills)
  def memory         = render(json: HermesApiService.list_memory)
  def missions       = render(json: Mission.order(created_at: :desc).limit(20))
  def profiles       = render(json: Profile.order(created_at: :desc).limit(20))
  def webhooks       = render(json: HermesApiService.list_webhooks)
  def usage          = render(json: HermesApiService.get_insights)

  # ── CLI Tools ─────────────────────────────────────────────────────
  def cli_doctor     = render(json: HermesApiService.run_doctor)
  def cli_backup     = render(json: HermesApiService.create_backup)
  def cli_security   = render(json: HermesApiService.run_security_audit)
  def cli_dump       = render(json: HermesApiService.get_dump)
  def cli_debug      = render(json: HermesApiService.create_debug_report)
  def cli_checkpoints = render(json: HermesApiService.get_checkpoints)
  def cli_proxy      = render(json: HermesApiService.get_proxy_status)
  def cli_secrets    = render(json: HermesApiService.get_secrets_status)
  def cli_pairing    = render(json: HermesApiService.list_pairing_users)
  def cli_insights   = render(json: HermesApiService.get_insights)
  def cli_hooks      = render(json: HermesApiService.list_hooks)
  def cli_mcp        = render(json: HermesApiService.list_mcp_servers)
  def cli_plugins    = render(json: HermesApiService.list_plugins)
  def cli_curator    = render(json: HermesApiService.curator_status)
  def cli_fallback   = render(json: HermesApiService.get_fallback_chain)

  # ── File Operations ───────────────────────────────────────────────
  def files
    path = params[:path] || ""
    data = HermesApiService.list_files(path)
    render json: data
  rescue HermesApiService::BackendError => e
    render json: { directories: [], files: [], error: e.message }
  end

  def files_read   = render(json: HermesApiService.read_file(params[:path]))
  def file_info    = render(json: HermesApiService.get_file_info(params[:path]))
  def file_delete  = render(json: HermesApiService.delete_file(params[:path]))
  def file_rename  = render(json: HermesApiService.rename_file(params[:path], params[:new_name]))
  def file_mkdir   = render(json: HermesApiService.create_directory(params[:path], params[:name]))

  # ── Profiles ────────────────────────────────────────────────────
  def profiles_list = render(json: HermesApiService.run_hermes_command(["profile", "list"]))
end
