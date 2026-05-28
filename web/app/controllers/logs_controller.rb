class LogsController < ApplicationController
  def index
    @level = params[:level].presence || "all"
    @lines = (params[:lines].presence || "50").to_i
    @logs = HermesApiService.get_logs(lines: @lines, level: @level)
    @entries = @logs['entries'] || []
  end

  def show
    @log_id = params[:id]
    @log = HermesApiService.get("/logs/#{@log_id}", default: nil)
  end

  # Turbo Stream endpoint for live log updates
  def live
    @level = params[:level].presence || "all"
    @lines = (params[:lines].presence || "50").to_i
    logs = HermesApiService.get_logs(lines: @lines, level: @level)
    @entries = logs['entries'] || []

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          'log-entries',
          partial: 'logs/entries',
          locals: { entries: @entries }
        )
      end
      format.html { redirect_to logs_path(level: @level, lines: @lines) }
    end
  end

  def tail
    @level = params[:level].presence || "all"
    @lines = (params[:lines].presence || "50").to_i
    logs = HermesApiService.get_logs(lines: @lines, level: @level)
    @entries = logs['entries'] || []
    render json: @entries
  end
end
