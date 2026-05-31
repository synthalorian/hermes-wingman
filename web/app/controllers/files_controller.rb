# frozen_string_literal: true

class FilesController < ApplicationController
  BASE = File.expand_path("~/.hermes")

  def show
    @path = params[:path] || ""
    @full_path = File.join(BASE, @path)
    if File.directory?(@full_path)
      @entries = Dir.entries(@full_path).sort - %w[. ..]
      @is_dir = true
    elsif File.file?(@full_path)
      @content = File.read(@full_path)
      @is_dir = false
    else
      @error = "Path not found: #{@path}"
    end
  rescue => e
    @error = e.message
  end

  def browse
    path = params[:path] || ""
    full = File.join(BASE, path)
    entries = Dir.exist?(full) ? (Dir.entries(full).sort - %w[. ..]) : []
    render json: { path: path, entries: entries }
  rescue => e
    render json: { error: e.message, entries: [] }
  end

  def read
    path = params[:path] || ""
    full = File.join(BASE, path)
    if File.file?(full)
      render json: { path: path, content: File.read(full) }
    else
      render json: { error: "File not found" }, status: :not_found
    end
  end

  def write
    path = params[:path] || ""
    full = File.join(BASE, path)
    File.write(full, params[:content])
    render json: { success: true, path: path }
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end
end
