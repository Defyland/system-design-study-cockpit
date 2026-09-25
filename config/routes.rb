Rails.application.routes.draw do
  get "login", to: "cockpit_sessions#new", as: :login
  post "login", to: "cockpit_sessions#create"
  delete "logout", to: "cockpit_sessions#destroy", as: :logout

  root "dashboard#index"
  get "study-cards/source/:id", to: "study_cards#source", as: :study_card_source
  get "study-cards/guide", to: "study_workspace#guide", as: :study_guide
  get "study-cards/map", to: "study_workspace#map", as: :study_map
  get "study-cards/configure", to: "study_workspace#configure", as: :study_configure
  post "study-cards/configure", to: "study_workspace#start", as: :start_study_workspace
  get "study-cards/review", to: "study_workspace#review", as: :study_review
  post "study-cards/review", to: "study_workspace#start_review", as: :start_study_review
  post "study-cards/bookmarks", to: "study_bookmarks#create", as: :study_bookmarks
  delete "study-cards/bookmarks/:card_key", to: "study_bookmarks#destroy", as: :study_bookmark
  get "study-cards/quiz", to: "study_quizzes#index", as: :study_quizzes
  post "study-cards/quiz", to: "study_quizzes#create"
  get "study-cards/quiz/:id", to: "study_quizzes#show", as: :study_quiz
  patch "study-cards/quiz/:id", to: "study_quizzes#update"
  resources :study_cards, path: "study-cards", only: %i[index create show update]

  get "arena", to: "arcade#show", as: :arena
  get "arena/warmup", to: "arcade#warmup", as: :arcade_warmup
  scope "arena", as: :arcade do
    resources :lessons, only: %i[create show], controller: :arcade_lessons do
      post :finish, on: :member
      resources :results, only: :create, controller: :arcade_exercise_results
    end
    resource :progress, only: :show, controller: :arcade_progress
  end

  resources :chapters, only: %i[index show], param: :slug
  resources :drills, only: %i[index]
  resource :study_plan, only: %i[show]
  resource :adaptive_session, only: %i[show]
  resource :english_arcade, only: %i[show], controller: :english_arcade do
    post :finish, on: :member
  end
  get "english-arcade", to: "english_arcade#show", as: :english_arcade_launcher
  resources :english_arcade_sessions, only: %i[create], path: "english-arcade/sessions", controller: :english_arcade
  post "english-arcade/best-answer-fill", to: "english_arcade#best_answer_fill", as: :english_arcade_best_answer_fill
  post "english-arcade/attempts", to: "english_arcade#attempt", as: :english_arcade_attempts
  post "english-arcade/voice/calls", to: "english_arcade_voice_calls#create", as: :english_arcade_voice_calls
  get "search", to: "search#index", as: :search
  resources :misconceptions, only: %i[index]
  resources :simulations, only: %i[index show], param: :slug do
    get :evaluate, on: :member
  end
  resources :simulation_attempts, only: %i[create]
  resources :side_tracks, only: %i[index show], param: :slug
  get "library/:kind", to: "library#index", as: :library
  get "library/:kind/:slug", to: "library#show", as: :library_document
  resources :study_missions, only: %i[create update]
  resources :learning_records, only: %i[create]
  resources :study_progresses, only: %i[update]
  resources :checkpoint_attempts, only: %i[create]
  resources :reminders, only: [] do
    post :snooze, on: :member
    post :dismiss, on: :member
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check
  get "health/content", to: "health_checks#content", as: :health_content

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"
end
