# frozen_string_literal: true

class HermesController < ApplicationController
  def update
    result = HermesApiService.hermes_update
    redirect_to config_path, notice: "Hermes update triggered."
  rescue HermesApiService::BackendError => e
    redirect_to config_path, alert: e.message
  end

  def command
    result = HermesApiService.run_hermes_command(params[:args] || [])
    render json: result
  rescue HermesApiService::BackendError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end
end
