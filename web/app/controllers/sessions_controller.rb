# frozen_string_literal: true

# Sessions — list, view, delete, and resume Hermes conversations.
class SessionsController < ApplicationController
  before_action :set_theme

  def index
    @sessions = HermesApiService.list_sessions(limit: 50)
    @sessions = [] unless @sessions.is_a?(Array)
  rescue HermesApiService::BackendError => e
    @error = e.message
    @sessions = []
  end

  def show
    @session = HermesApiService.get_session(params[:id])
  rescue HermesApiService::BackendError => e
    redirect_to sessions_path, alert: "Session not found: #{e.message}"
  end

  def destroy
    HermesApiService.delete_session(params[:id])
    redirect_to sessions_path, notice: "Session deleted."
  rescue HermesApiService::BackendError => e
    redirect_to sessions_path, alert: "Failed to delete session: #{e.message}"
  end

  def resume
    session[:resume_session_id] = params[:id]
    redirect_to chat_path, notice: "Session loaded for resume."
  end

  private

  def set_theme
    @theme = session[:theme] || "synthwave84"
  end
end