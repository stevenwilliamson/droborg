Rails.application.config.middleware.use OmniAuth::Builder do
  provider :github, ENV["GITHUB_KEY"], ENV["GITHUB_SECRET"], scope: "user:email,repo,read:org"
end
