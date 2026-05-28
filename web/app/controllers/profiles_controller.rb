# frozen_string_literal: true

class ProfilesController < ApplicationController
  before_action :set_profile, only: [:show, :edit, :update, :destroy, :apply]

  def index
    @profiles = Profile.order(created_at: :desc)
  end

  def show
  end

  def new
    @profile = Profile.new
  end

  def create
    @profile = Profile.new(profile_params)
    if @profile.save
      redirect_to @profile, notice: "Profile created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @profile.update(profile_params)
      redirect_to @profile, notice: "Profile updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @profile.destroy
    redirect_to profiles_path, notice: "Profile deleted."
  end

  def apply
    # Apply profile settings via HermesApiService
    if @profile.default_model.present?
      HermesApiService.switch_model(@profile.default_model)
    end
    redirect_to profiles_path, notice: "Profile '#{@profile.name}' applied."
  rescue HermesApiService::BackendError => e
    redirect_to profiles_path, alert: "Apply failed: #{e.message}"
  end

  private

  def set_profile
    @profile = Profile.find(params[:id])
  end

  def profile_params
    params.require(:profile).permit(:name, :description, :default_model, :default_provider, :config_overrides, :skills, :theme)
  end
end
