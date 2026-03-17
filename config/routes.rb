Rails.application.routes.draw do
  root "posts#index"

  # Auth
  get  "/login",   to: "sessions#new",     as: :login
  post "/login",   to: "sessions#create"
  delete "/logout", to: "sessions#destroy", as: :logout
  get  "/signup",  to: "users#new",        as: :signup
  post "/signup",  to: "users#create"

  # OAuth callbacks
  get "/auth/:provider/callback", to: "omniauth_callbacks#handle"
  get "/auth/failure",            to: "omniauth_callbacks#failure"

  # Forum
  resources :posts do
    resources :replies, only: [ :create, :destroy, :edit, :update ]
  end

  resources :users, only: [] do
    resources :bans, only: [ :new, :create ]
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check
end
