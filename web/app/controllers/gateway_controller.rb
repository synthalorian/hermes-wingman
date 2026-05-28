# frozen_string_literal: true

class GatewayController < ApplicationController
  def show
    @platforms = HermesApiService.get_gateway_status
    @platforms = [] unless @platforms.is_a?(Array)
  rescue HermesApiService::BackendError => e
    @error = e.message
    @platforms = []
  end

  def toggle
    result = HermesApiService.toggle_gateway(params[:action])
    redirect_to gateway_path, notice: "Gateway #{params[:action]} completed."
  rescue HermesApiService::BackendError => e
    redirect_to gateway_path, alert: e.message
  end
end
