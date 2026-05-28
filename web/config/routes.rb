Rails.application.routes.draw do
  # Root → Dashboard
  root "dashboard#show"

  # Health check
  get "up", to: "dashboard#health"

  # Chat
  resource :chat, only: [:show, :create], controller: :chat do
    collection do
      post :send_message
      get :stream, defaults: { format: :json }
    end
  end

  # Sessions
  resources :sessions, only: [:index, :show, :destroy] do
    member do
      post :resume
    end
  end

  # Models
  resources :models, only: [:index] do
    member do
      post :switch
      post :probe
    end
    collection do
      get :providers
    end
  end

  # Config
  resource :config, only: [:show, :update], controller: :config

  # Logs
  resources :logs, only: [:index, :show], controller: :logs do
    collection do
      get :tail
      get :live
    end
  end

  # Cron Jobs
  resources :cron_jobs, only: [:index], controller: :cron do
    member do
      post :toggle
      post :run
    end
  end

  # Gateway
  resource :gateway, only: [:show], controller: :gateway do
    member do
      post :toggle
    end
  end

  # Providers
  resources :providers, only: [:index] do
    member do
      post :probe
    end
  end

  # Skills
  resources :skills, only: [:index] do
    member do
      post :toggle
    end
  end

  # Memory
  resources :memory, only: [:index, :show, :update, :destroy], controller: :memory do
    collection do
      post :search
    end
  end

  # File Explorer
  resource :files, only: [:show], controller: :files do
    get :browse
    get :read
    put :write
  end

  # Live Tools
  resource :tools, only: [:show], controller: :tools

  # Inspector
  resources :inspector, only: [:index, :show], controller: :inspector do
    collection do
      get :session
    end
  end

  # Missions
  resources :missions do
    member do
      post :run
      post :cancel
    end
  end

  # Orchestration
  resource :orchestration, only: [:show], controller: :orchestration do
    collection do
      post :create_run
      get :status
    end
  end

  # Profiles
  resources :profiles do
    member do
      post :apply
    end
  end

  # Providers
  resources :providers, only: [:index]

  # CLI Tools
  resource :cli_tools, only: [:show], controller: :cli_tools, path: '/cli_tools'

  # Gateway Setup
  resource :gateway_setup, only: [:show], controller: :gateway_setup, path: '/gateway_setup'

  # Webhooks
  resources :webhooks

  # Usage / Analytics
  resource :usage, only: [:show], controller: :usage

  # Setup wizard
  resource :setup, only: [:show], controller: :setup do
    collection do
      post :install
      post :configure
    end
  end

  # Hermes management
  namespace :hermes do
    post :update
    post :command
  end

  # API routes (JSON endpoints for Stimulus controllers)
  namespace :api do
    get :health
    get :status
    get :models
    get :sessions
    get :logs
    get :cron
    get :gateway
    get :gateway_platforms
    get :providers
    get :auth_status
    get :skills
    get :memory
    get :missions
    get :profiles
    get :webhooks
    get :usage
    # CLI tools
    get :cli_doctor
    post :cli_backup
    get :cli_security
    get :cli_dump
    get :cli_debug
    get :cli_checkpoints
    get :cli_proxy
    get :cli_secrets
    get :cli_pairing
    get :cli_insights
    get :cli_hooks
    get :cli_mcp
    get :cli_plugins
    get :cli_curator
    get :cli_fallback
    # File operations
    get :files
    get :files_read
    get :file_info
    post :file_delete
    post :file_rename
    post :file_mkdir
    # Profile list
    get :profiles_list
  end

  # Theme switch
  post "theme/:name", to: "theme#switch", as: :switch_theme
end
