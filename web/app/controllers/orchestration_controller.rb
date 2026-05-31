# frozen_string_literal: true

class OrchestrationController < ApplicationController
  def show
    @runs = OrchestrationRun.order(created_at: :desc).limit(20)
  end

  def create_run
    @run = OrchestrationRun.new(
      name: params[:name] || "Orchestration #{Time.current.to_fs(:short)}",
      description: params[:description],
      status: "pending",
      agent_count: params[:agents]&.split(",")&.length || 1,
      agents: params[:agents] || "hermes",
      tasks: params[:tasks] || "[]"
    )
    if @run.save
      @run.update(status: "running", started_at: Time.current)
      # TODO: dispatch to agent orchestrator
      redirect_to orchestration_path, notice: "Orchestration started."
    else
      redirect_to orchestration_path, alert: "Failed to create orchestration."
    end
  end

  def status
    render json: OrchestrationRun.order(created_at: :desc).limit(10)
  end
end
