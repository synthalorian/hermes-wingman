# frozen_string_literal: true

class GatewaySetupController < ApplicationController
  def show
    @platforms = HermesApiService.get_gateway_platforms rescue {}
    @status = HermesApiService.get_gateway_status rescue {}
  end
end
