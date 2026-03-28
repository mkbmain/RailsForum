Rails.application.routes.draw do
  root "posts#index"

  # Auth
  get  "/login",   to: "sessions#new",     as: :login
  post "/login",   to: "sessions#create"
  delete "/logout", to: "sessions#destroy", as: :logout
  get  "/signup",  to: "users#new",        as: :signup
  post "/signup",  to: "users#create"
  resources :password_resets, only: [ :new, :create, :edit, :update ], param: :token
  resources :email_verifications, only: [:show], param: :token do
    collection { post :resend }
  end

  # OAuth callbacks
  get "/auth/:provider/callback", to: "omniauth_callbacks#handle"
  get "/auth/failure",            to: "omniauth_callbacks#failure"

  # Forum
  get "/search", to: "search#index"

  resources :posts do
    member { patch :restore }
    resources :flags,     only: [ :create ]
    resources :reactions, only: [ :create, :destroy ]
    resources :replies,   only: [ :create, :destroy, :edit, :update ] do
      member { patch :restore }
      resources :reactions, only: [ :create, :destroy ]
      resources :flags,     only: [ :create ]
    end
  end

  resources :users, only: [ :show, :edit, :update ] do
    resources :bans, only: [ :new, :create ]
  end

  namespace :admin do
    root to: "dashboard#index"
    resources :users, only: [ :index, :show ] do
      member do
        patch :promote
        patch :demote
      end
    end
    resources :flags, only: [ :index ] do
      member { patch :dismiss }
    end
    resources :categories, only: [ :index, :new, :create, :edit, :update, :destroy ] do
      member do
        patch :move_up
        patch :move_down
      end
    end
  end

  resources :notifications, only: [ :index ] do
    collection { patch :read_all }
    member     { patch :read }
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check
end
