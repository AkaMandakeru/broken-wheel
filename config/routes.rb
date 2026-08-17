Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check
  get "manifest", to: "pwa#manifest", as: :pwa_manifest, defaults: { format: :json }
  get "service-worker", to: "pwa#service_worker", as: :pwa_service_worker

  devise_for :users, controllers: {
    registrations: "users/registrations"
  }

  root "home#index"

  get "profile", to: "profiles#show"
  get "profile/edit", to: "profiles#edit", as: :edit_profile
  patch "profile", to: "profiles#update"
  put "profile", to: "profiles#update"

  post   "/auth/strava",          to: "oauth#connect",     as: :auth_strava
  get    "/auth/strava/callback", to: "oauth#callback",   as: :auth_strava_callback
  delete "/auth/strava",          to: "oauth#disconnect", as: :disconnect_strava

  get "achievements", to: "achievements#index", as: :achievements
  get "integrations", to: "integrations#index", as: :integrations
  resources :workouts, only: [:index, :create] do
    collection do
      get  :strava_activities
      post :import_strava
    end
  end
  resources :challenges, only: [:index, :show] do
    member do
      post :join
      get :invite
    end
    resources :timeline_posts, only: [:index, :create], path: "timeline" do
      resources :comments, only: [:create], controller: "timeline_post_comments"
    end
  end

  resources :clubs, only: [:index, :show, :create] do
    member do
      post :join
      delete :leave
    end
  end

  resources :events, only: [:index, :show] do
    resource :participation, only: [:create, :update, :destroy], controller: "event_participations"
  end

  resources :support_tickets, only: [:index, :new, :create, :show] do
    resources :messages, only: [:create], controller: "support_messages"
  end

  resource :push_subscription, only: [:create, :destroy]

  resources :seasons, only: [:index, :show] do
    # `id` optional: posting without one claims everything pending.
    resources :claims, only: [:create], controller: "season_claims"
    post "claims/:id", to: "season_claims#create", as: :claim
  end

  namespace :admin do
    root "dashboard#index"
    resources :challenges
    resources :events
    resources :seasons do
      member { get :export }
      resources :season_challenges, only: [:create, :destroy]
      resources :season_objectives, only: [:create, :destroy]
      resources :season_rewards, only: [:create, :destroy]
    end
    resources :season_imports, only: [:new, :create] do
      collection { get :template }
    end
    resources :features, only: [:index, :update], param: :id
    resources :support_tickets, only: [:index, :show, :update] do
      resources :messages, only: [:create], controller: "support_messages"
    end
  end

  get "/switch_locale/:locale", to: "locales#switch", as: :switch_locale
end
