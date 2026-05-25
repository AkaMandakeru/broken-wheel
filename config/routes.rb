Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check
  get "manifest", to: "pwa#manifest", as: :pwa_manifest, defaults: { format: :json }
  get "service-worker", to: "pwa#service_worker", as: :pwa_service_worker

  devise_for :users, controllers: {
    registrations: "users/registrations"
  }

  root "home#index"

  get "profile", to: "profiles#show"
  patch "profile", to: "profiles#update"
  put "profile", to: "profiles#update"

  post   "/auth/strava",          to: "oauth#connect",     as: :auth_strava
  get    "/auth/strava/callback", to: "oauth#callback",   as: :auth_strava_callback
  delete "/auth/strava",          to: "oauth#disconnect", as: :disconnect_strava

  get "achievements", to: "achievements#index", as: :achievements
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

  get "/switch_locale/:locale", to: "locales#switch", as: :switch_locale
end
