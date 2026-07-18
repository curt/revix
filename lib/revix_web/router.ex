defmodule RevixWeb.Router do
  use RevixWeb, :router

  import RevixWeb.PersonAuth

  pipeline :browser do
    plug Plug.RewriteOn, [:x_forwarded_host, :x_forwarded_port, :x_forwarded_proto]
    plug :accepts, ["html", "json", "activity", "geo"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {RevixWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_person
  end

  pipeline :api do
    plug Plug.RewriteOn, [:x_forwarded_host, :x_forwarded_port, :x_forwarded_proto]
    plug :accepts, ["json"]
    plug RevixWeb.Plugs.RobotsHeader
  end

  pipeline :federation do
    plug Plug.RewriteOn, [:x_forwarded_host, :x_forwarded_port, :x_forwarded_proto]
    plug :accepts, ["activity", "json"]
    plug RevixWeb.Plugs.RobotsHeader
  end

  pipeline :robots_noindex do
    plug RevixWeb.Plugs.RobotsHeader
  end

  pipeline :robots_index do
    plug RevixWeb.Plugs.RobotsHeader, allow_index: true
  end

  scope "/", RevixWeb do
    pipe_through [:browser, :robots_index]

    get "/", PageController, :index
  end

  scope "/", RevixWeb do
    pipe_through [:browser, :robots_noindex]

    get "/credits", CreditsController, :index
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:revix, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: RevixWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", RevixWeb do
    pipe_through [:browser, :redirect_if_person_is_authenticated, :robots_noindex]

    get "/people/register", PersonRegistrationController, :new
    post "/people/register", PersonRegistrationController, :create
  end

  scope "/", RevixWeb do
    pipe_through [:browser, :require_authenticated_person, :robots_noindex]

    get "/people/settings", PersonSettingsController, :edit
    put "/people/settings", PersonSettingsController, :update
    get "/people/settings/confirm/:token", PersonSettingsController, :confirm_email

    get "/api/places/search", PlaceController, :search
    post "/api/likes", LikeController, :create
    delete "/api/likes", LikeController, :delete
    post "/api/entry_people", EntryPeopleController, :create
    delete "/api/entry_people", EntryPeopleController, :delete
    get "/api/people/search", PersonSearchController, :search
    post "/checkins/:id/retransform_images", CheckinController, :retransform_images
    post "/posts/:id/retransform_images", PostController, :retransform_images
    post "/notes", NoteController, :create
    put "/notes/:id", NoteController, :update
    delete "/notes/:id", NoteController, :delete

    live_session :authenticated,
      on_mount: [{RevixWeb.Live.PersonAuth, :require_authenticated_person}] do
      live "/checkins/new", CheckinNewLive, :new
      live "/checkins/:id/edit", CheckinEditLive, :edit
      live "/places/new", PlaceNewLive, :new
      live "/places/:id/checkins/new", CheckinFromPlaceLive, :new
      live "/places/:id/edit", PlaceEditLive, :edit
      live "/places/:id/merge", PlaceMergeLive, :merge
      live "/pings", PingsLive, :index
      live "/following", FollowingLive, :index
      live "/posts/new", PostNewLive, :new
      live "/posts/:id/edit", PostEditLive, :edit
    end
  end

  scope "/", RevixWeb do
    pipe_through :federation

    post "/people/:id/inbox", InboxController, :create
    get "/people/:id/followers", PersonCollectionController, :followers
    get "/people/:id/following", PersonCollectionController, :following
    get "/people/:id/outbox", PersonCollectionController, :outbox
    get "/people/:id/liked", PersonCollectionController, :liked
    get "/entries/:id/likes", EntryCollectionController, :likes
    get "/entries/:id/replies", EntryCollectionController, :replies
  end

  scope "/", RevixWeb do
    pipe_through [:browser, :robots_noindex]

    get "/people/signin", PersonSessionController, :new
    get "/people/signin/:token", PersonSessionController, :confirm
    post "/people/signin", PersonSessionController, :create
    delete "/people/signout", PersonSessionController, :delete
  end

  scope "/", RevixWeb do
    pipe_through [:browser, :robots_noindex]

    get "/notes/:id", NoteController, :show
  end

  scope "/", RevixWeb do
    pipe_through [:browser, :robots_index]

    get "/people/:id", PersonController, :show
    get "/@:username", PersonController, :show
    get "/places", PlaceController, :index
    get "/checkins", CheckinController, :index
    get "/posts", PostController, :index

    get "/places/:id", PlaceController, :show
    get "/places/:id/:slug", PlaceController, :show
    get "/places/:id/:country/:slug", PlaceController, :show
    get "/places/:id/:country/:city/:slug", PlaceController, :show
    get "/places/:id/:country/:secondary/:city/:slug", PlaceController, :show
    get "/checkins/:id", CheckinController, :show
    get "/checkins/:id/:slug", CheckinController, :show
    get "/checkins/:id/:country/:slug", CheckinController, :show
    get "/checkins/:id/:country/:city/:slug", CheckinController, :show
    get "/checkins/:id/:country/:secondary/:city/:slug", CheckinController, :show
    get "/posts/:id", PostController, :show
    get "/posts/:id/:year/:month/:day/:slug", PostController, :show
  end

  scope "/", RevixWeb do
    get "/.well-known/webfinger", WebfingerController, :show
    get "/.well-known/nodeinfo", NodeInfoController, :well_known
    get "/nodeinfo/:version", NodeInfoController, :version
    get "/identicon/:id", IdenticonController, :show
    get "/feed.atom", FeedController, :index
    get "/robots.txt", RobotsController, :index
    get "/sitemap.xml", SitemapController, :index
    get "/sitemap/places.xml", SitemapController, :places
    get "/sitemap/checkins.xml", SitemapController, :checkins
    get "/sitemap/posts.xml", SitemapController, :posts
  end
end
