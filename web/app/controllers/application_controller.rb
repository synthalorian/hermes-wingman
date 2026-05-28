# frozen_string_literal: true

class ApplicationController < ActionController::Base
  allow_browser versions: :modern

  rescue_from HermesApiService::BackendError do |e|
    respond_to do |format|
      format.html do
        @error = e.message
        render "shared/backend_error", status: :service_unavailable
      end
      format.json { render json: { error: e.message }, status: :service_unavailable }
    end
  end
end
