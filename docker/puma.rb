require "etc"

if GC.respond_to?(:copy_on_write_friendly=)
  GC.copy_on_write_friendly = true
end

# Configure workers and threads
threads ENV.fetch("PUMA_THREADS", 4).to_i, ENV.fetch("PUMA_THREADS", 4).to_i

workers_count = ENV.fetch("PUMA_WORKERS", Etc.nprocessors).to_i
workers workers_count
if workers_count > 1
  preload_app!
end

worker_timeout 60

bind "tcp://0.0.0.0:#{ENV.fetch("PORT", "80")}"

quiet true
