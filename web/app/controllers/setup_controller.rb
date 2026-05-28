# frozen_string_literal: true

class SetupController < ApplicationController
  def show
    @detect = HermesApiService.detect_setup
  rescue HermesApiService::BackendError => e
    @error = e.message
    @detect = {}
  end

  def install
    result = HermesApiService.install_hermes(method: params[:method] || "pip")
    redirect_to setup_path, notice: "Installation started."
  rescue HermesApiService::BackendError => e
    redirect_to setup_path, alert: "Install failed: #{e.message}"
  end

  def configure
    result = HermesApiService.auto_configure
    redirect_to setup_path, notice: "Auto-configuration complete."
  rescue HermesApiService::BackendError => e
    redirect_to setup_path, alert: "Configuration failed: #{e.message}"
  end
end
