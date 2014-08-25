use Mix.Config

config :chatty,
  host: "irc.freenode.net",
  port: 6667,
  nickname: "testbotunique",
  channels: ["test-secret-channel"],
  logging_enabled: true
