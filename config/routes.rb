Rails.application.routes.draw do
  root "dashboard#index"

  resources :chapters, only: %i[index show], param: :slug
  resources :drills, only: %i[index]
  resource :adaptive_session, only: %i[show]
  resources :misconceptions, only: %i[index]
  resources :simulations, only: %i[index show], param: :slug do
    get :evaluate, on: :member
  end
  resources :simulation_attempts, only: %i[create]
  get "library/:kind", to: "library#index", as: :library
  get "library/:kind/:slug", to: "library#show", as: :library_document
  resources :study_progresses, only: %i[update]
  resources :checkpoint_attempts, only: %i[create]
  resources :reminders, only: [] do
    post :snooze, on: :member
    post :dismiss, on: :member
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"
end
