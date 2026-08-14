Rails.application.routes.draw do
  resource :session
  resources :passwords, param: :token

  resources :students, except: :destroy do
    member do
      post :archive
      post :unarchive
    end
  end

  resources :class_groups do
    member do
      put :members
    end
  end

  resources :exams, path: "tests", as: :tests do
    member do
      post :publish
      post :close
      get :results
      get :live
    end

    resources :questions, only: %i[create update destroy]
    resources :assignments, only: %i[index create] do
      collection do
        get :manage
        post :bulk_revoke
      end
    end
  end

  resources :assignments, only: [] do
    member do
      post :revoke
      post :regenerate_token
    end
  end

  resources :attempts, only: %i[show update]

  # module "take" avoids clashing with the Student ActiveRecord model
  scope "/t/:token", module: :take, as: :student do
    get "/", to: "portals#show", as: :portal
    post "start", to: "runs#create", as: :start
    get "run", to: "runs#show", as: :run
    put "answers", to: "answers#upsert", as: :answers
    post "submit", to: "submissions#create", as: :submit
    get "done", to: "submissions#show", as: :done
  end

  get "up" => "rails/health#show", as: :rails_health_check

  root "home#index"
end
