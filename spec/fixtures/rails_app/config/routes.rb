Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check
  # Declared before `resources :widgets` so it isn't shadowed by the :show
  # route. It names an action WidgetsController does not define -- that is
  # deliberate: rails_controller must report it under routes_without_action.
  get "widgets/legacy", to: "widgets#removed_long_ago"
  resources :widgets, only: %i[index show edit update]
  resources :pings, only: [:index]
  namespace :admin do
    resources :reports, only: [:index]
  end

  mount WidgetAdmin::Engine, at: "/widget_admin"

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"
end
