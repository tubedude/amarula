defmodule Amarula.ProfileTest do
  use ExUnit.Case, async: true

  # Amarula.Profile builds IQs via Protocol.Profile.Ops (100% covered on its own),
  # round-trips them through Connection.query_iq/3, and parses the reply. These
  # tests call the REAL facade against an offline sandbox connection: each call
  # runs in a Task (query_iq blocks), the test captures the outbound IQ off the
  # frame_sink, injects a synthetic reply, and asserts the parsed result — so the
  # target-resolution (self vs other jid) and reply handling are the module's own.
  #
  # Fake placeholder jids only (repo PII rule).

  alias Amarula.Profile
  alias Amarula.Protocol.Binary.{Node, NodeUtils}

  # The sandbox's default logged-in identity (Amarula.Testing.default_auth).
  @me_jid "10000000000@s.whatsapp.net"
  @other_jid "15550001234@s.whatsapp.net"
  @group_jid "120363000000000042@g.us"
  @pic_url "https://pps.whatsapp.net/v/t61/12345.jpg"

  setup do
    profile = :"profile_#{System.unique_integer([:positive])}"
    dir = Path.join(System.tmp_dir!(), "amarula_profile_#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf(dir) end)

    {:ok, pid} =
      Amarula.Testing.start_offline(
        profile: profile,
        storage: {Amarula.Storage.File, root: dir}
      )

    on_exit(fn -> Amarula.stop(pid) end)
    {:ok, pid: pid}
  end

  # Run `fun` (a blocking Profile call) in a Task, answer the outbound IQ with
  # `reply_fun.(iq)`, and return {result, iq} so the test can assert both sides.
  defp round_trip(pid, fun, reply_fun) do
    task = Task.async(fn -> fun.() end)
    iq = recv_frame()
    send(pid, {:inject_node, reply_fun.(iq)})
    {Task.await(task, 2000), iq}
  end

  defp recv_frame do
    receive do
      {:frame_out, %Node{tag: "iq"} = node} -> node
      {:frame_out, _other} -> recv_frame()
    after
      1000 -> flunk("timed out waiting for the outbound IQ")
    end
  end

  defp iq_id(iq), do: NodeUtils.get_attr(iq, "id")

  defp result_reply(id, content \\ nil) do
    %Node{tag: "iq", attrs: %{"type" => "result", "id" => id}, content: content}
  end

  defp error_reply(id) do
    %Node{
      tag: "iq",
      attrs: %{"type" => "error", "id" => id},
      content: [%Node{tag: "error", attrs: %{"code" => "401"}, content: nil}]
    }
  end

  defp picture_reply(id, url) do
    result_reply(id, [%Node{tag: "picture", attrs: %{"url" => url}, content: nil}])
  end

  describe "picture_url/3" do
    test "queries w:profile:picture for the jid and returns the URL", %{pid: pid} do
      {result, iq} =
        round_trip(
          pid,
          fn -> Profile.picture_url(pid, @other_jid) end,
          fn iq -> picture_reply(iq_id(iq), @pic_url) end
        )

      assert NodeUtils.get_attr(iq, "xmlns") == "w:profile:picture"
      assert NodeUtils.get_attr(iq, "type") == "get"
      assert NodeUtils.get_attr(iq, "target") == @other_jid

      picture = NodeUtils.get_binary_node_child(iq, "picture")
      # Default is the small preview.
      assert NodeUtils.get_attr(picture, "type") == "preview"
      assert NodeUtils.get_attr(picture, "query") == "url"

      assert result == {:ok, @pic_url}
    end

    test ":image asks for the full-size picture", %{pid: pid} do
      {result, iq} =
        round_trip(
          pid,
          fn -> Profile.picture_url(pid, @group_jid, :image) end,
          fn iq -> picture_reply(iq_id(iq), @pic_url) end
        )

      picture = NodeUtils.get_binary_node_child(iq, "picture")
      assert NodeUtils.get_attr(picture, "type") == "image"
      assert NodeUtils.get_attr(iq, "target") == @group_jid
      assert result == {:ok, @pic_url}
    end

    test "no picture (or not visible) returns {:ok, nil}", %{pid: pid} do
      {result, _iq} =
        round_trip(
          pid,
          fn -> Profile.picture_url(pid, @other_jid) end,
          fn iq -> result_reply(iq_id(iq)) end
        )

      assert result == {:ok, nil}
    end

    test "an error reply surfaces as {:error, node}", %{pid: pid} do
      {result, _iq} =
        round_trip(
          pid,
          fn -> Profile.picture_url(pid, @other_jid) end,
          fn iq -> error_reply(iq_id(iq)) end
        )

      assert {:error, %Node{}} = result
    end
  end

  describe "update_picture/3" do
    test "for our own jid omits the target attr (Baileys self shape)", %{pid: pid} do
      jpeg = <<0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3>>

      {result, iq} =
        round_trip(
          pid,
          fn -> Profile.update_picture(pid, @me_jid, jpeg) end,
          fn iq -> result_reply(iq_id(iq)) end
        )

      assert NodeUtils.get_attr(iq, "xmlns") == "w:profile:picture"
      assert NodeUtils.get_attr(iq, "type") == "set"
      # Self: sending target for our own jid makes the server never reply.
      assert NodeUtils.get_attr(iq, "target") == nil

      picture = NodeUtils.get_binary_node_child(iq, "picture")
      assert picture.content == jpeg

      assert result == :ok
    end

    test "for a group carries the group as target", %{pid: pid} do
      {result, iq} =
        round_trip(
          pid,
          fn -> Profile.update_picture(pid, @group_jid, <<1, 2, 3>>) end,
          fn iq -> result_reply(iq_id(iq)) end
        )

      assert NodeUtils.get_attr(iq, "target") == @group_jid
      assert result == :ok
    end

    test "an error reply surfaces as {:error, node}", %{pid: pid} do
      {result, _iq} =
        round_trip(
          pid,
          fn -> Profile.update_picture(pid, @me_jid, <<1>>) end,
          fn iq -> error_reply(iq_id(iq)) end
        )

      assert {:error, %Node{}} = result
    end
  end

  describe "remove_picture/2" do
    test "for our own jid is a bare set with no target and no content", %{pid: pid} do
      {result, iq} =
        round_trip(
          pid,
          fn -> Profile.remove_picture(pid, @me_jid) end,
          fn iq -> result_reply(iq_id(iq)) end
        )

      assert NodeUtils.get_attr(iq, "xmlns") == "w:profile:picture"
      assert NodeUtils.get_attr(iq, "type") == "set"
      assert NodeUtils.get_attr(iq, "target") == nil
      assert iq.content == nil

      assert result == :ok
    end

    test "for another jid carries it as target", %{pid: pid} do
      {result, iq} =
        round_trip(
          pid,
          fn -> Profile.remove_picture(pid, @other_jid) end,
          fn iq -> result_reply(iq_id(iq)) end
        )

      assert NodeUtils.get_attr(iq, "target") == @other_jid
      assert result == :ok
    end
  end

  describe "update_status/2" do
    test "sets the status text via the status xmlns", %{pid: pid} do
      {result, iq} =
        round_trip(
          pid,
          fn -> Profile.update_status(pid, "out for mangoes") end,
          fn iq -> result_reply(iq_id(iq)) end
        )

      assert NodeUtils.get_attr(iq, "xmlns") == "status"
      assert NodeUtils.get_attr(iq, "type") == "set"

      status = NodeUtils.get_binary_node_child(iq, "status")
      assert status.content == "out for mangoes"

      assert result == :ok
    end

    test "an error reply surfaces as {:error, node}", %{pid: pid} do
      {result, _iq} =
        round_trip(
          pid,
          fn -> Profile.update_status(pid, "nope") end,
          fn iq -> error_reply(iq_id(iq)) end
        )

      assert {:error, %Node{}} = result
    end
  end
end
