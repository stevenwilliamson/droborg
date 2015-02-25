Rails.application.config.middleware.use OmniAuth::Builder do
  provider :github, Rails.configuration.x.github_key, Rails.configuration.x.github_secret, scope: "user:email,repo,read:org"
end
