WidgetAdmin::Engine.routes.draw do
  resources :audits, only: %i[index show]
end
