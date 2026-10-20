import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :truco_on, TrucoOnWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "QQZFqd7Q25Z83Uk/pdAp2UFcIo1A3uzKalvy8b5hcuYYjO94qwaVBqOD2fiHoTC+",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime
