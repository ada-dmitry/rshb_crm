Rails.application.routes.draw do
  resource :session, only: %i[ new create destroy ]
  get "crm" => "dashboard#index", as: :crm
  scope :crm do
    resources :customers, only: %i[ index show ]
    resources :segments, only: :show
    resources :campaigns, only: %i[ index new create show edit update ] do
      get :preview, on: :member
      post :confirm, on: :member
      post :launch, on: :member
      post :simulate_events, on: :member
    end
  end
  get "up" => "rails/health#show", as: :rails_health_check

  root "home#index"
end
