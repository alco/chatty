defmodule Chatty.Hook do
  defstruct [
    id: nil,
    type: :text,
    direct: false,
    exclusive: false,
    fn: nil,
    chan: nil,
    public_only: true,
  ]
end
