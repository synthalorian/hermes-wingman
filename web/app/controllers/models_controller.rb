# frozen_string_literal: true

# Models — browse, switch, and probe Hermes AI models & providers.
class ModelsController < ApplicationController
  def index
    @models_raw = HermesApiService.list_models
    @models = @models_raw
    @local_models  = @models_raw.fetch("local", [])
    @cloud_models  = @models_raw.fetch("cloud", [])
    @fallback_models = @models_raw.fetch("fallback", [])
    @current_model = @models_raw["current"] || @models_raw["model"]
  rescue HermesApiService::BackendError => e
    @error = e.message
    @models_raw = {}
    @local_models = @cloud_models = @fallback_models = []
    @current_model = nil
  end

  def switch
    model_name = params[:id]
    result = HermesApiService.switch_model(model_name)
    flash[:notice] = "Switched to #{model_name}"
    redirect_to models_path
  rescue HermesApiService::BackendError => e
    flash[:alert] = "Switch failed: #{e.message}"
    redirect_to models_path
  end

  def probe
    model_name = params[:id]
    result = HermesApiService.probe_model(model_name)
    flash[:notice] = "Probe result: #{result}"
    redirect_to models_path
  rescue HermesApiService::BackendError => e
    flash[:alert] = "Probe failed: #{e.message}"
    redirect_to models_path
  end

  def providers
    @providers = HermesApiService.list_providers
  rescue HermesApiService::BackendError => e
    @error = e.message
    @providers = []
  end
end