defmodule Chatty.Connection.UserInfo do
  defstruct [
    host: '',
    port: 0,
    nickname: "",
    password: "",
    channels: [],
  ]
end
