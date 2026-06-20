defmodule Amarula.Protocol.Messages.Poll do
  @moduledoc """
  Poll vote tally, ported from Baileys `getAggregateVotesInPollMessage`
  (`src/Utils/messages.ts`).

  A vote's `selectedOptions` are SHA-256 hashes of the chosen option names, so
  tallying maps each poll option's `sha256(option_name)` back to its name and
  collects the voters whose decrypted votes contain that hash.

  Decrypt incoming votes with `Amarula.Protocol.Messages.PollCrypto.decrypt_vote/2`
  first; pass the results here as `{voter_jid, %PollVoteMessage{}}` tuples.
  """

  alias Amarula.Protocol.Proto

  @type tally_entry :: %{name: String.t(), voters: [String.t()]}

  @doc """
  Tally `votes` against a poll-creation `message`. `votes` is a list of
  `{voter_jid, %Proto.Message.PollVoteMessage{}}` (decrypted). Returns a list of
  `%{name: option_name, voters: [voter_jid]}`, one per poll option (plus an
  `"Unknown"` bucket for hashes not matching any option).
  """
  @spec tally(Proto.Message.t(), [{String.t(), struct()}]) :: [tally_entry()]
  def tally(%Proto.Message{} = message, votes) do
    # option SHA-256 hash => %{name, voters: []}, in option order.
    base =
      message
      |> options()
      |> Enum.map(fn name -> {option_hash(name), %{name: name, voters: []}} end)

    by_hash = Map.new(base)
    order = Enum.map(base, fn {hash, _} -> hash end)

    {by_hash, order} =
      Enum.reduce(votes, {by_hash, order}, fn {voter, vote}, acc ->
        Enum.reduce(selected(vote), acc, fn hash, {map, ord} ->
          case Map.fetch(map, hash) do
            {:ok, entry} ->
              {Map.put(map, hash, add_voter(entry, voter)), ord}

            :error ->
              {Map.put(map, hash, %{name: "Unknown", voters: [voter]}), ord ++ [hash]}
          end
        end)
      end)

    Enum.map(order, &Map.fetch!(by_hash, &1))
  end

  @doc "The SHA-256 hash WhatsApp identifies a poll option by (the vote payload's `selectedOptions`)."
  @spec option_hash(String.t()) :: binary()
  def option_hash(name), do: :crypto.hash(:sha256, name)

  # The option names from whichever poll-creation variant is set.
  defp options(%Proto.Message{pollCreationMessage: %{options: o}}) when is_list(o), do: names(o)
  defp options(%Proto.Message{pollCreationMessageV2: %{options: o}}) when is_list(o), do: names(o)
  defp options(%Proto.Message{pollCreationMessageV3: %{options: o}}) when is_list(o), do: names(o)
  defp options(_message), do: []

  defp names(options), do: Enum.map(options, & &1.optionName)

  defp selected(%{selectedOptions: opts}) when is_list(opts), do: opts
  defp selected(_vote), do: []

  defp add_voter(%{voters: voters} = entry, voter), do: %{entry | voters: voters ++ [voter]}
end
