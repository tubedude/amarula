defmodule Amarula.Protocol.Messages.Types do
  @moduledoc """
  Type definitions for WhatsApp messages.
  """

  @type message_key :: %{
          remote_jid: String.t(),
          from_me: boolean(),
          id: String.t(),
          participant: String.t() | nil
        }

  @type message_content :: map()

  @type wa_message :: %{
          key: message_key(),
          message: message_content(),
          message_timestamp: non_neg_integer(),
          status: atom()
        }

  @type message_upsert_type :: :notify | :append

  @type send_message_options :: %{
          optional(:quoted) => wa_message(),
          optional(:ephemeral_expiration) => non_neg_integer(),
          optional(:timestamp) => DateTime.t(),
          optional(:message_id) => String.t(),
          optional(:context_info) => map()
        }
end
