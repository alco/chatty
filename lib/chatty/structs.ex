defmodule Chatty.ConnServer.State do
  @moduledoc false
  defstruct hooks: []
end

defmodule Chatty.ConnServer.UserInfo do
  @moduledoc false
  defstruct host: '', port: 0, nickname: "", password: "", channels: []
end
