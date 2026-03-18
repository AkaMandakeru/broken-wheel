Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check
  get "manifest", to: "pwa#manifest", as: :pwa_manifest, defaults: { format: :json }
  get "service-worker", to: "pwa#service_worker", as: :pwa_service_worker

  devise_for :users, controllers: {
    registrations: "users/registrations"
  }

  root "challenges#index"

  get "profile", to: "profiles#show"
  patch "profile", to: "profiles#update"
  put "profile", to: "profiles#update"

  resources :workouts, only: [:index, :create]
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
end
