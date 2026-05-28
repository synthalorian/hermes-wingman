# frozen_string_literal: true

class SkillsController < ApplicationController
  def index
    @skills = HermesApiService.list_skills
    @skills = [] unless @skills.is_a?(Array)
  rescue HermesApiService::BackendError => e
    @error = e.message
    @skills = []
  end

  def toggle
    redirect_to skills_path, notice: "Skill toggled (backend pending for full implementation)."
  end
end
