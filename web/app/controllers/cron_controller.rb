# frozen_string_literal: true

class CronController < ApplicationController
  def index
    @jobs = HermesApiService.list_cron_jobs
    @jobs = [] unless @jobs.is_a?(Array)
  rescue HermesApiService::BackendError => e
    @error = e.message
    @jobs = []
  end

  def toggle
    HermesApiService.toggle_gateway(params[:id] == "pause" ? "stop" : "start")
    redirect_to cron_jobs_path, notice: "Job toggled."
  rescue HermesApiService::BackendError => e
    redirect_to cron_jobs_path, alert: e.message
  end

  def run
    redirect_to cron_jobs_path, notice: "Job triggered (backend pending)."
  end
end
