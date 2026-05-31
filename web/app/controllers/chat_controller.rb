# frozen_string_literal: true

# Chat — send messages to Hermes and get responses
class ChatController < ApplicationController
  def show
    @sessions = HermesApiService.list_sessions(limit: 20)
  rescue HermesApiService::BackendError => e
    @error = e.message
    @sessions = []
  end

  def send_message
    message = params[:message]
    session_id = params[:session_id]

    unless message.present?
      return render json: { error: "Message is required" }, status: :unprocessable_entity
    end

    # Use non-streaming chat — post to /chat and get the response
    result = HermesApiService.chat(message, session_id: session_id)
    render json: result
  rescue HermesApiService::BackendError => e
    render json: { error: e.message }, status: :service_unavailable
  end
end