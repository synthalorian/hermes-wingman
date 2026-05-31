# frozen_string_literal: true

class UsageController < ApplicationController
  def show
    @snapshots = UsageSnapshot.order(recorded_at: :desc).limit(30)
    @health = HermesApiService.health rescue {}
    @models = HermesApiService.list_models rescue {}
  rescue HermesApiService::BackendError => e
    @error = e.message
  end
end
