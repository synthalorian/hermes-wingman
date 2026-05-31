# frozen_string_literal: true

class InspectorController < ApplicationController
  def index
  end

  def show
  end

  def session_detail
    @session_id = params[:id]
    render :show
  end
end
