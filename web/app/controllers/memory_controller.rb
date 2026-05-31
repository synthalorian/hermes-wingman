# frozen_string_literal: true

class MemoryController < ApplicationController
  def index
    @entries = CachedMemory.order(created_at: :desc).limit(50)
  rescue StandardError => e
    @error = e.message
    @entries = []
  end

  def show
    @entry = CachedMemory.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to memory_index_path, alert: "Memory entry not found."
  end

  def update
    @entry = CachedMemory.find(params[:id])
    if @entry.update(memory_params)
      redirect_to memory_path(@entry), notice: "Memory updated."
    else
      render :show, status: :unprocessable_entity
    end
  end

  def destroy
    CachedMemory.find(params[:id]).destroy
    redirect_to memory_index_path, notice: "Memory deleted."
  end

  def search
    query = params[:query]
    @entries = CachedMemory.where("content LIKE ? OR entry_key LIKE ?", "%#{query}%", "%#{query}%").limit(50)
    render :index
  end

  private

  def memory_params
    params.require(:cached_memory).permit(:content, :memory_type, :tags)
  end
end
