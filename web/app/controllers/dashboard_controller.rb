# frozen_string_literal: true

# Dashboard — HUD overview of the Hermes agent status.
class DashboardController < ApplicationController
  def show
    @health = HermesApiService.health
    @models = HermesApiService.list_models
    @sessions_raw = HermesApiService.list_sessions(limit: 5)
  rescue HermesApiService::BackendError => e
    @error = e.message
    @health = {}
    @models = {}
    @sessions_raw = []
  end

  def health
    render json: HermesApiService.health
  rescue HermesApiService::BackendError => e
    render json: { error: e.message, status: "unreachable" }, status: :service_unavailable
  end
end
