import Config

# Environment configuration
config :zdbeam,
  # Set to false in test environment to prevent GenServers from starting
  start_genservers: config_env() != :test

# Default values (can be overridden by CLI arguments)
config :zdbeam,
  # Must be provided via --app-id
  discord_application_id: nil,
  # Default: 5 seconds
  check_interval: :timer.seconds(5)

# Logger configuration
config :logger, :console,
  format: "[$level] $message\n",
  metadata: [:pid]

# Default log level (can be overridden via --log-level)
config :logger, level: :info
