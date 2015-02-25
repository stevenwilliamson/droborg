Rails.application.config.middleware.use OmniAuth::Builder do
  provider :github, Rails.configuration.app.github_key, Rails.configuration.app.github_secret, scope: "user:email,repo,read:org"
end
