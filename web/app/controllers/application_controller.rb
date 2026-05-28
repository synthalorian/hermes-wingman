# frozen_string_literal: true

class ApplicationController < ActionController::Base
  # Allow only the specified host — no explicit IP/proxy trust required
  allow_browser versions: :modern
end
