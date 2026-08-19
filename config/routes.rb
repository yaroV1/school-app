Rails.application.routes.draw do
  resource :session
  resources :passwords, param: :token

  resources :class_groups do
    member do
      delete :remove_member
      get :students
    end
    resources :students, only: %i[create]
    resources :subjects, only: %i[create]
  end

  resources :students, except: %i[index new create destroy] do
    member do
      post :archive
      post :unarchive
    end
  end

  resources :subjects, except: %i[index new create] do
    member do
      get :stats
    end
    resources :exams, path: "tests", only: %i[new create]
  end

  resources :exams, path: "tests", as: :tests, except: %i[index new create] do
    member do
      post :publish
      post :close
      get :results
      get :live
      get :print
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
