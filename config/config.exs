import Config

# Amarula's OWN dev/test config — NOT loaded when Amarula is a dependency (a
# consumer configures their own app). Per-connection settings (profile, storage,
# version, timeouts, browser, …) are passed to `Amarula.new/1`; their defaults
# live in `Amarula.Config`. Only the genuinely app-global seams belong here.

# Pluggable backends (a module per behaviour). These are the defaults already, so
# the lines are illustrative — uncomment to override globally:
# config :amarula, :default_storage_adapter, Amarula.Storage.File
# config :amarula, :retry_cache_adapter, Amarula.RetryCache.ETS

# Logger: a CONSUMER controls their own level. In our dev/test we keep it quiet by
# default (Amarula's own logs are mostly :debug; lifecycle/errors are :info+).
# See `Amarula.Config` docs for how a consumer silences Amarula specifically.
config :logger, level: :info

if config_env() == :test do
  config :logger, level: :warning
end
