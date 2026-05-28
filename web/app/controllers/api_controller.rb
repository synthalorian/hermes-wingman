# frozen_string_literal: true

# API endpoints for Stimulus controllers — returns JSON directly from the Rust backend.
class ApiController < ApplicationController
  def health
    render json: HermesApiService.health
  rescue HermesApiService::BackendError => e
    render json: { error: e.message }
  end

  def status
    render json: HermesApiService.health
  rescue HermesApiService::BackendError => e
    render json: { error: e.message }
  end

  def models
    render json: HermesApiService.list_models
  rescue HermesApiService::BackendError => e
    render json: { error: e.message }
  end

  def sessions
    render json: HermesApiService.list_sessions
  rescue HermesApiService::BackendError => e
    render json: { error: e.message }
  end

  def logs
    render json: HermesApiService.get_logs
  rescue HermesApiService::BackendError => e
    render json: { error: e.message }
  end

  def cron
    render json: HermesApiService.list_cron_jobs
  rescue HermesApiService::BackendError => e
    render json: { error: e.message }
  end

  def gateway
    render json: HermesApiService.get_gateway_status
  rescue HermesApiService::BackendError => e
    render json: { error: e.message }
  end

  def gateway_platforms
    data = HermesApiService.get_gateway_platforms
    render json: data
  rescue HermesApiService::BackendError => e
    render json: { error: e.message }
  end

  def providers
    render json: HermesApiService.list_providers
  rescue HermesApiService::BackendError => e
    render json: { error: e.message }
  end

  def auth_status
    render json: HermesApiService.auth_status
  rescue HermesApiService::BackendError => e
    render json: { error: e.message }
  end

  def skills
    render json: HermesApiService.list_skills
  rescue HermesApiService::BackendError => e
    render json: { error: e.message }
  end

  def memory
    render json: HermesApiService.list_memory
  rescue HermesApiService::BackendError => e
    render json: { error: e.message }
  end

  def missions
    render json: Mission.order(created_at: :desc).limit(20)
  rescue StandardError => e
    render json: { error: e.message }
  end

  def profiles
    render json: Profile.order(created_at: :desc).limit(20)
  rescue StandardError => e
    render json: { error: e.message }
  end

  def webhooks
    render json: HermesApiService.list_webhooks
  rescue HermesApiService::BackendError => e
    render json: { error: e.message }
  end

  def usage
    render json: HermesApiService.get_insights
  rescue HermesApiService::BackendError => e
    render json: { error: e.message }
  end

  # ── CLI Tools ─────────────────────────────────────────────────────

  def cli_doctor
    render json: HermesApiService.run_doctor
  rescue HermesApiService::BackendError => e
    render json: { error: e.message }
  end

  def cli_backup
    render json: HermesApiService.create_backup
  rescue HermesApiService::BackendError => e
    render json: { error: e.message }
  end

  def cli_security
    render json: HermesApiService.run_security_audit
  rescue HermesApiService::BackendError => e
    render json: { error: e.message }
  end

  def cli_dump
    render json: HermesApiService.get_dump
  rescue HermesApiService::BackendError => e
    render json: { error: e.message }
  end

  def cli_debug
    render json: HermesApiService.create_debug_report
  rescue HermesApiService::BackendError => e
    render json: { error: e.message }
  end

  def cli_checkpoints
    render json: HermesApiService.get_checkpoints
  rescue HermesApiService::BackendError => e
    render json: { error: e.message }
  end

  def cli_proxy
    render json: HermesApiService.get_proxy_status
  rescue HermesApiService::BackendError => e
    render json: { error: e.message }
  end

  def cli_secrets
    render json: HermesApiService.get_secrets_status
  rescue HermesApiService::BackendError => e
    render json: { error: e.message }
  end

  def cli_pairing
    render json: HermesApiService.list_pairing_users
  rescue HermesApiService::BackendError => e
    render json: { error: e.message }
  end

  def cli_insights
    render json: HermesApiService.get_insights
  rescue HermesApiService::BackendError => e
    render json: { error: e.message }
  end

  def cli_hooks
    render json: HermesApiService.list_hooks
  rescue HermesApiService::BackendError => e
    render json: { error: e.message }
  end

  def cli_mcp
    render json: HermesApiService.list_mcp_servers
  rescue HermesApiService::BackendError => e
    render json: { error: e.message }
  end

  def cli_plugins
    render json: HermesApiService.list_plugins
  rescue HermesApiService::BackendError => e
    render json: { error: e.message }
  end

  def cli_curator
    render json: HermesApiService.curator_status
  rescue HermesApiService::BackendError => e
    render json: { error: e.message }
  end

  def cli_fallback
    render json: HermesApiService.get_fallback_chain
  rescue HermesApiService::BackendError => e
    render json: { error: e.message }
  end

  # ── File Operations ───────────────────────────────────────────────

  def files
    path = params[:path] || ''
    data = HermesApiService.list_files(path)
    render json: data
  rescue HermesApiService::BackendError => e
    render json: { directories: [], files: [], error: e.message }
  end

  def files_read
    render json: HermesApiService.read_file(params[:path])
  rescue HermesApiService::BackendError => e
    render json: { error: e.message }
  end

  def file_info
    render json: HermesApiService.get_file_info(params[:path])
  rescue HermesApiService::BackendError => e
    render json: { error: e.message }
  end

  def file_delete
    render json: HermesApiService.delete_file(params[:path])
  rescue HermesApiService::BackendError => e
    render json: { error: e.message }
  end

  def file_rename
    render json: HermesApiService.rename_file(params[:path], params[:new_name])
  rescue HermesApiService::BackendError => e
    render json: { error: e.message }
  end

  def file_mkdir
    render json: HermesApiService.create_directory(params[:path], params[:name])
  rescue HermesApiService::BackendError => e
    render json: { error: e.message }
  end

  # ── Profiles ────────────────────────────────────────────────────

  def profiles_list
    # Run hermes profile list via CLI proxy
    result = HermesApiService.run_hermes_command(["profile", "list"])
    render json: result
  rescue HermesApiService::BackendError => e
    render json: { error: e.message }
  end
end
