require 'bundler/capistrano'

# As we're not using the capistrano deploy receipe, mimic it's variables to
# support the whenever gem
def _cset(name, *args, &block)
  unless exists?(name)
    set(name, *args, &block)
  end
end

set :application, "droborg"
set :user, "deploy"
set :default_shell, '/bin/bash -l'
set :bundle_cmd, 'bundle'

set :repo, "git@github.com:afcapel/droborg.git"
set :github_repo, "afcapel/droborg.git"
set :repository, "git@github.com:afcapel/droborg.git"
set :scm, "git"

set :god_service, "unicorn-droborg"
set :default_environment, { 'LANG' => 'en_US.UTF-8' }

set :app_root, "/var/apps/droborg"

set :current_release, File.join(app_root, "current")
set :current_revision,  `/usr/bin/git rev-parse --short HEAD`.chomp
set :latest_release, current_release
set :shared_path, File.join(app_root, "shared")

default_run_options[:pty] = true
ssh_options[:forward_agent] = true

if ENV['BRANCH']
  set :branch, ENV['BRANCH']
else
  set(:branch) do
    default_branch = `git describe --contains --all --exact-match HEAD`.chomp
    branch = Capistrano::CLI.ui.ask("Branch to deploy (or press return to deploy from #{default_branch}): ")
    branch = default_branch if branch == ''
    branch = "remotes/origin/#{branch}"
    branch
  end
end

# Environments
task :vmlocal do
  set :cluster, "vmlocal"
  set :rails_env, 'vmlocal'
  set :repo, "steven@192.168.224.1:git/droborg"

  server "192.168.224.187", :droborg_web, :db
  server "192.168.224.188", :dorborg_jobserver
end

task :production do
  set :cluster, "production"
  set :rails_env, "production"

  server "10.8.104.44", :droborg_web, :db
  server "10.8.104.45", :droborg_jobserver
end

namespace :deploy do
  before 'cold',       'setup:check'
  before 'deploy',     'setup:check'
  before 'migrations', 'setup:check'

  task :default do
    setup.update_code
    setup.post_update
    setup.restart
  end

  task :cold do
    setup.prepare
    setup.post_update
    setup.restart
  end

  task :migrations do
    setup.update_code
    setup.post_update
    setup.migrate
    setup.restart
  end
end

namespace :service do
  before('start', 'setup:check')
  before('stop',  'setup:check')

  task :start do
    run "god start #{god_service}"
  end
  task :stop do
    run "god stop #{god_service}"
  end
end

namespace :setup do
  task :prepare do
    run "mkdir -p #{app_root} #{shared_path} #{current_release}"
    run "cd #{current_release} && rm -Rf * .git* .r* .bundle .watchr && git clone --quiet #{repo} . && git reset --hard #{branch}"
  end

  task :update_code do
    run "cd #{current_release} && git remote update origin && git reset --hard #{branch} && git clean -fd"
  end

  task :post_update do
    run "mkdir -p #{shared_path}/log #{shared_path}/tmp"
    run "cd #{current_release} && ln -nfs #{shared_path}/log log"
    run "cd #{current_release} && ln -nfs #{shared_path}/tmp tmp"

    bundle.install
    run "cd #{current_release} && bundle exec rake assets:precompile"
  end

  task :restart_dr_servers, :only => { :rolling_restart => false }, :on_no_matching_servers => :continue do
    run "god stop #{god_service}"
    # Wait for service to stop
    run "until god status #{god_service} | grep '#{god_service}: unmonitored' ; do sleep 1 ; done"
    run "god start #{god_service}"
  end

  task :restart_job_servers, :roles => :droborg_job_server, :on_no_matching_servers => :continue do
    run "god stop dj-droborg"
    run "until god status dj-droborg | grep 'dj-droborg: unmonitored' ; do sleep 1 ; done"
    run "god start dj-droborg"
  end

  task :restart, :roles => :droborg_web, :max_hosts => 1 do

    setup.restart_job_servers

    find_servers(:except => {:rolling_restart => false}).each do |server|

      # Remove server from lb
      run "touch #{File.join(fetch(:app_root), 'shared/disable')}", :hosts => server.host

      # restart unicorn via god
      run "god stop #{god_service}", :hosts => server.host
      run "until god status #{god_service} | grep '#{god_service}: unmonitored' ; do sleep 1 ; done", :hosts => server.host
      run "god start #{god_service}", :hosts => server.host

      # Check server is respnding to requests before moving on
      #run "loop=120 ; echo \"Waiting for 200 OK from unicorn\" ; until `curl --output /dev/null --location --silent --fail --header 'Host: dev.freeagent.com' \"http://127.0.0.1:1080\"`; do printf \".\" ; sleep 1 ; let \"loop = ${loop} - 1\" ; if [ $loop -eq 0 ]; then echo \"Giving UP\" ; exit 1; fi ; done", :hosts => server.host

      # Server responding to requests again add it back to the load balancer
      run "rm #{File.join(fetch(:app_root), 'shared/disable')}", :hosts => server.host
    end
  end

  task :migrate, :roles => :db do
    run "cd #{current_release} && RAILS_ENV=#{rails_env} bundle exec rake db:migrate"
  end

  task :check do
    unless exists?(:cluster)
      puts "ERROR:  Please invoke with environment 'cap env task' e.g. 'cap staging deploy'"
      exit
    end
  end
end

namespace :freeagent do
  desc "Installs the DR newrelic.yml template on DR servers"
  task :disable_newrelic_in_dr_environment, :roles => [:dr] do
    run <<-CMD
      cp #{current_release}/config/newrelic.yml.dr #{current_release}/config/newrelic.yml
    CMD
  end
end
