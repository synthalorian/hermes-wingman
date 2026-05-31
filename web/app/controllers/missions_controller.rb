# frozen_string_literal: true

class MissionsController < ApplicationController
  before_action :set_mission, only: [:show, :edit, :update, :destroy, :run, :cancel]

  def index
    @missions = Mission.order(created_at: :desc)
  end

  def show
  end

  def new
    @mission = Mission.new
  end

  def create
    @mission = Mission.new(mission_params)
    if @mission.save
      redirect_to @mission, notice: "Mission created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @mission.update(mission_params)
      redirect_to @mission, notice: "Mission updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @mission.destroy
    redirect_to missions_path, notice: "Mission deleted."
  end

  def run
    @mission.update(status: "running", last_run_at: Time.current)
    HermesApiService.chat(@mission.prompt)
    @mission.update(status: "completed", next_run_at: @mission.schedule.present? ? Time.current + 1.hour : nil)
    redirect_to @mission, notice: "Mission executed."
  rescue HermesApiService::BackendError => e
    @mission.update(status: "failed")
    redirect_to @mission, alert: "Execution failed: #{e.message}"
  end

  def cancel
    @mission.update(status: "cancelled")
    redirect_to @mission, notice: "Mission cancelled."
  end

  private

  def set_mission
    @mission = Mission.find(params[:id])
  end

  def mission_params
    params.require(:mission).permit(:name, :description, :prompt, :schedule, :status, :max_turns)
  end
end
