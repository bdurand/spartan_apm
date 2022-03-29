begin
  require "bundler/setup"
rescue LoadError
  warn "You must `gem install bundler` and `bundle install` to run rake tasks"
end

require "rdoc/task"

RDoc::Task.new(:rdoc) do |rdoc|
  rdoc.rdoc_dir = "rdoc"
  rdoc.title = "SpartanAPM"
  rdoc.options << "--line-numbers"
  rdoc.rdoc_files.include("README.md")
  rdoc.rdoc_files.include("lib/**/*.rb")
end

begin
  require "bundler/gem_tasks"
rescue Bundler::GemspecError
  warn "Gem tasks not available because gemspec not defined"
end

begin
  require "rspec/core/rake_task"
  RSpec::Core::RakeTask.new(:spec)
  task default: :spec
rescue LoadError
  warn "You must install rspec to run the spec rake tasks"
end

desc "run the specs using appraisal"
task :appraisals do
  exec "bundle exec appraisal rake spec"
end

namespace :appraisals do
  desc "install all the appraisal gemspecs"
  task :install do
    exec "bundle exec appraisal install"
  end
end

namespace :load_sample_data do
  task :sample_stats do
    require "json"
    require_relative "lib/spartan_apm"
    SpartanAPM.ttl = 60 * 60 * 24
    json = File.read(File.join(__dir__, "sample_data", "sample_stats.json"))
    data = JSON.parse(json)
    minutes = data.keys.last.to_i - data.keys.first.to_i
    bucket = SpartanAPM.bucket(Time.now - ((minutes + 1) * 60))
    data.values.each do |action_data|
      action_data.each do |action, host_data|
        host_data.each do |host, stat_data|
          SpartanAPM.host = host
          measures = []
          stat_data["app"].each_with_index do |process_values, process_index|
            (process_values.size - 1).times do |request_index|
              measure = SpartanAPM::Measure.new("web", action)
              measures << measure
              stat_data.each do |name, values|
                vals = Array(values[process_index])
                measure.timers[name] = vals[request_index].to_f / 1000.0
                measure.counts[name] = vals.last
              end
              if rand(100) < 2
                begin
                  error_class = [StandardError, ArgumentError, Timeout::Error][rand(3)]
                  raise error_class, "Unexpected error"
                rescue => e
                  measure.capture_error(e)
                end
              end
            end
          end
          SpartanAPM::Persistence.store!(bucket, measures)
        end
      end
      bucket += 1
    end
  end

  task :sample_hourly do
    require "json"
    require_relative "lib/spartan_apm"
    json = File.read(File.join(__dir__, "sample_data", "sample_hourly_stats.json"))
    data = JSON.parse(json)
    hours = data.last["hour"]
    start_time = SpartanAPM::Persistence.truncate_to_hour(Time.now - ((hours + 1) * 60 * 60))
    data.each do |hour_data|
      hour = hour_data.delete("hour")
      hour_data["hour"] = (start_time + (hour * 60 * 60)).to_i
      SpartanAPM::Persistence.send(:add_hourly_stats, "web", hour_data)
    end
  end

  task :sample_daily do
    require "json"
    require_relative "lib/spartan_apm"
    json = File.read(File.join(__dir__, "sample_data", "sample_daily_stats.json"))
    data = JSON.parse(json)
    days = data.last["day"]
    start_time = SpartanAPM::Persistence.truncate_to_date(Time.now - ((days + 1) * 24 * 60 * 60))
    data.each do |day_data|
      day = day_data.delete("day")
      day_data["day"] = (start_time + (day * 24 * 60 * 60)).to_i
      SpartanAPM::Persistence.send(:add_daily_stats, "web", day_data)
    end
  end
end

desc "Download the plotly.js javascript file and store in the public directory"
task :download_plotly_js do
  require_relative "lib/spartan_apm"
  require "net/http"
  response = Net::HTTP.get_response(URI(SpartanAPM.plotly_js_url))
  response.value
  public_dir = File.join(__dir__, "public")
  Dir.mkdir(public_dir) unless File.exist?(public_dir)
  File.write(File.join(public_dir, "plotly.js"), response.body)
end

desc "load sample stats for local development"
task load_sample_data: ["load_sample_data:sample_stats", "load_sample_data:sample_hourly", "load_sample_data:sample_daily"]
