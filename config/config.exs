use Mix.Config

config :chatty, [
  host: "irc.freenode.net",
  port: 6667,
  nickname: "testbotunique",
  channels: ["test-secret-channel"],
]

# Use a custom format with a single line break at the end
config :logger, :console, [
  format: "$time $metadata[$level] $levelpad$message\n",
  level: :debug,
]

config :logger, [
  handle_otp_reports: true,
]
