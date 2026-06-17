Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  root to: redirect("/ticker/index.html")

  namespace :api do
    get "scores", to: "scores#index"
  end
end
