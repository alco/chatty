defmodule Chatty.IRCHookHandler do
  use GenEvent

  def handle_event(message, hook_manager) do
    hook_manager.process_message(message)
    {:ok, hook_manager}
  end
end
