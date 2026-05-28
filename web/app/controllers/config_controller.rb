# frozen_string_literal: true

class ConfigController < ApplicationController
  def show
    @config = HermesApiService.get_config
    @raw = @config.is_a?(Hash) ? (@config["raw"] || @config.to_yaml) : @config.to_s
  rescue HermesApiService::BackendError => e
    @error = e.message
    @raw = ""
  end

  def update
    HermesApiService.write_config(params[:content])
    redirect_to config_path, notice: "Configuration saved."
  rescue HermesApiService::BackendError => e
    redirect_to config_path, alert: "Save failed: #{e.message}"
  end
end
