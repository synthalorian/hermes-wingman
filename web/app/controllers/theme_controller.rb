# frozen_string_literal: true

# Handles theme switching. Session-persisted, no auth required.
class ThemeController < ApplicationController
  # POST /theme/:name
  def switch
    name = params[:name]
    # Validate against known theme names
    valid = %w[synthwave84 synthwave84-light outrun vaporwave cyberpunk hermes
               zeus hera poseidon hades ares apollo artemis athena aphrodite
               dionysus demeter hephaestus hestia nyx eos hypnos iris tyche
               thanatos nemesis hecate light dark]
    if valid.include?(name)
      session[:theme] = name
    end
    redirect_back fallback_location: "/"
  end
end
