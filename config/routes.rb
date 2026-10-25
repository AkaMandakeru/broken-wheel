Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check
  get "manifest", to: "pwa#manifest", as: :pwa_manifest, defaults: { format: :json }
  get "service-worker", to: "pwa#service_worker", as: :pwa_service_worker, defaults: { format: :js }

  devise_for :users, controllers: {
    registrations: "users/registrations"
  }

  root "home#index"

  get "profile", to: "profiles#show"
  get "profile/edit", to: "profiles#edit", as: :edit_profile
  get   "profile/appearance", to: "appearances#show",   as: :profile_appearance
  patch "profile/appearance", to: "appearances#update"
  post  "profile/appearance/claim", to: "appearances#claim", as: :claim_profile_appearance
  patch "profile", to: "profiles#update"
  put "profile", to: "profiles#update"

  # Unsubscribe link in engagement emails — authenticated by the signed token.
  get    "email/unsubscribe/:token", to: "email_subscriptions#show",    as: :email_unsubscribe
  post   "email/unsubscribe/:token", to: "email_subscriptions#create"
  delete "email/unsubscribe/:token", to: "email_subscriptions#destroy"

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
    post "dismiss_announcement", to: "season_announcements#dismiss", as: :dismiss_announcement
  end

  # --- Mobile API (docs/MOBILE_API_PLAN.md) ----------------------------------
  namespace :api, defaults: { format: :json } do
    namespace :v1 do
      resource :config, only: :show, controller: "config"

      namespace :auth do
        post   "register", to: "registrations#create"
        post   "login",    to: "sessions#create"
        post   "refresh",  to: "sessions#refresh"
        delete "logout",   to: "sessions#destroy"
        post   "password", to: "passwords#create"
      end

      resources :uploads, only: :create

      # Profile, locker, achievements
      resource :me, only: [ :show, :update, :destroy ], controller: "me" do
        get :stats
      end
      get    "me/locker",       to: "locker#index",   as: :locker
      put    "me/locker/:kind", to: "locker#update",  as: :locker_kind
      delete "me/locker/:kind", to: "locker#destroy"
      post   "me/locker/claim", to: "locker#claim",   as: :locker_claim
      get    "achievements",    to: "achievements#index"

      # Seasons
      resources :seasons, only: [ :index, :show ] do
        scope module: :seasons do
          resources :challenges, only: :index
          resources :dailies, only: :index
          resources :objectives, only: :index
          resources :rewards, only: :index
          resources :activities, only: :index
          resource :community, only: :show, controller: "community"
          resource :leaderboard, only: :show
          # `id` optional: posting without one claims everything pending.
          resources :claims, only: [ :index, :create ]
          post "claims/:id", to: "claims#create", as: :claim
          post "announcement/dismiss", to: "announcements#dismiss", as: :dismiss_announcement
        end
      end

      # Workouts and Strava
      resources :workouts, only: [ :index, :create ]
      get    "integrations",      to: "integrations#index"
      post   "strava/authorize",  to: "strava#authorize",  as: :strava_authorize
      post   "strava/callback",   to: "strava#callback",   as: :strava_callback
      get    "strava/activities", to: "strava#activities", as: :strava_activities
      post   "strava/import",     to: "strava#import",     as: :strava_import
      delete "strava",            to: "strava#destroy",    as: :strava

      # Challenges, clubs, events, support, moderation
      resources :challenges, only: [ :index, :show ] do
        member do
          post :join
          get :invite
        end
        resources :timeline_posts, only: [ :index, :create ], path: "timeline", module: :challenges do
          resources :comments, only: :create
        end
      end
      resources :clubs, only: [ :index, :show, :create ] do
        member do
          post :join
          delete :membership, action: :leave
        end
      end
      resources :events, only: [ :index, :show ] do
        resource :participation, only: [ :create, :update, :destroy ], module: :events
      end
      namespace :support do
        resources :tickets, only: [ :index, :show, :create ] do
          resources :messages, only: :create
        end
      end
      resources :reports, only: :create
      get    "blocks",          to: "blocks#index"
      post   "blocks/:user_id", to: "blocks#create", as: :block
      delete "blocks/:user_id", to: "blocks#destroy"

      # Native push
      resources :devices, only: [ :create, :destroy ], param: :token, constraints: { token: %r{[^/]+} }
    end
  end

  # Universal links / app links: lets shared links open the app.
  get ".well-known/apple-app-site-association", to: "well_known#apple_app_site_association", as: :apple_app_site_association
  get ".well-known/assetlinks.json", to: "well_known#assetlinks", as: :assetlinks, defaults: { format: :json }

  # Image URLs for the API, on CDN_HOST when set. Proxy routes, so the CDN can
  # cache the bytes (redirect routes would hand out short-lived storage URLs).
  direct :cdn_image do |model, options|
    options = options.merge(host: ENV["CDN_HOST"], protocol: "https", port: nil) if ENV["CDN_HOST"].present?

    if model.respond_to?(:signed_id)
      route_for(:rails_service_blob_proxy, model.signed_id, model.filename, options)
    else
      route_for(:rails_blob_representation_proxy, model.blob.signed_id, model.variation.key, model.blob.filename, options)
    end
  end

  namespace :admin do
    root "dashboard#index"
    resources :challenges
    resources :events
    resources :seasons do
      member do
        get :export
        post :announce
      end
      resources :season_challenges, only: [:create, :update, :destroy] do
        member do
          post :send_test_reminder
          post :send_reminder
        end
      end
      resources :season_objectives, only: [:create, :destroy]
      resources :season_rewards, only: [:create, :destroy] do
        member { post :distribute }
      end
      # Test data for staging and development; 404s anywhere else.
      resource :sandbox, only: [:show], controller: "season_sandboxes" do
        post :enroll
        post :workouts
        post :challenges
        post :objectives
        post :dailies
        post :level
        post :xp
        post :premium
        post :reward
        post :recalculate
        post :community
        post :bots, action: :add_bots
        delete :bots, action: :remove_bots
        delete :reset
      end
    end
    resources :season_imports, only: [:new, :create] do
      collection { get :template }
    end
    resources :cosmetics, except: [:show]
    resources :features, only: [:index, :update], param: :id
    resources :content_reports, only: [ :index, :show, :update ]
    resources :support_tickets, only: [:index, :show, :update] do
      resources :messages, only: [:create], controller: "support_messages"
    end
  end

  # Job dashboard (Solid Queue), admins only — see config/initializers/mission_control.rb.
  mount MissionControl::Jobs::Engine, at: "/admin/jobs"

  get "/switch_locale/:locale", to: "locales#switch", as: :switch_locale
end
