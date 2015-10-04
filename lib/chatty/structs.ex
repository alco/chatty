defmodule Chatty.Connection.State do
  @moduledoc false
  defstruct hooks: []
end

defmodule Chatty.Connection.UserInfo do
  @moduledoc false
  defstruct host: '', port: 0, nickname: "", password: "", channels: []
end
