Rails.application.routes.draw do
  devise_for :users
  get 'pages/home'

  # The priority is based upon order of creation: first created -> highest priority.
  # See how all your routes lay out with "rake routes".

  # You can have the root of your site routed with "root"
  # root 'welcome#index'
  #root :controller => 'static', :action => '/public/home.html'
  #root '/public/home.html'
  root 'pages#home'

  get 'home2' => 'pages#home'

  get 'discussion' => 'pages#discussion'

  get 'uploadprofile' => 'pages#uploadprofile'
  post 'uploadprofile' => 'pages#createchart'

  get 'livechart/:roast_id' => 'pages#livechart'
  get 'livechartjson/:roast_id' => 'pages#livechart_json'

  # mailing list
  get '/submitemail' => 'pages#submitemail'

  # ******* API *******
  get 'api1/cmd' => 'api#get_command'
  get 'api1/log' => 'api#log'

end
