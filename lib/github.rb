module Github
  extend self


  def find_repo(repo_name)
    client.repository(repo_name)
  end

  def repos
    org.rels[:repos].get.data
  end

  def org
    @org ||= client.organization(Rails.configuration.app.github_org)
  end

  def client
    @client ||= Octokit::Client.new(access_token: Rails.configuration.app.github_token)
  end
end
