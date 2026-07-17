defmodule Wasmex.PipeTest do
  use ExUnit.Case, async: true
  import TestHelper, only: [t: 1]

  alias Wasmex.Pipe
  doctest Pipe

  defp build_pipe(_) do
    {:ok, pipe} = Pipe.new()
    %{pipe: pipe}
  end

  describe t(&Pipe.size/1) do
    setup :build_pipe

    test "new pipes have a size of 0", %{pipe: pipe} do
      assert Pipe.size(pipe) == 0
    end

    test "pipes with content, report a positive size", %{pipe: pipe} do
      Pipe.write(pipe, "123")
      assert Pipe.size(pipe) == 3
    end

    test "seek position doesn't change the pipes size", %{pipe: pipe} do
      Pipe.write(pipe, "ninechars")
      assert Pipe.size(pipe) == 9
      assert Pipe.seek(pipe, 2)
      assert Pipe.size(pipe) == 9
    end
  end

  describe t(&Pipe.read/1) <> t(&Pipe.write/2) <> t(&Pipe.seek/2) do
    setup :build_pipe

    test "allows reads and writes", %{pipe: pipe} do
      assert Pipe.read(pipe) == ""

      assert {:ok, 13} == Pipe.write(pipe, "Hello, World!")
      # current read position of that pipe is at EOL
      assert Pipe.read(pipe) == ""
      assert Pipe.seek(pipe, 0) == :ok
      assert Pipe.read(pipe) == "Hello, World!"
    end

    test "#{t(&Pipe.seek/2)} sets pipe position", %{pipe: pipe} do
      Pipe.write(pipe, "Hello, World!")
      Pipe.seek(pipe, 7)
      Pipe.write(pipe, "Wasmex")
      Pipe.seek(pipe, 0)
      assert Pipe.read(pipe) == "Hello, Wasmex"
    end
  end

  describe t(&Pipe.new/1) do
    test "an unbounded pipe accepts any write" do
      {:ok, pipe} = Pipe.new()
      assert {:ok, 5} == Pipe.write(pipe, "hello")
      assert {:ok, 5} == Pipe.write(pipe, "world")
      assert Pipe.size(pipe) == 10
    end

    test "nil capacity is the same as an unbounded pipe" do
      {:ok, pipe} = Pipe.new(nil)
      assert {:ok, 5} == Pipe.write(pipe, "hello")
      assert Pipe.size(pipe) == 5
    end

    test "writes up to the capacity are accepted" do
      {:ok, pipe} = Pipe.new(5)
      assert {:ok, 5} == Pipe.write(pipe, "hello")
      assert Pipe.size(pipe) == 5
    end

    test "a write beyond the capacity is refused in full" do
      {:ok, pipe} = Pipe.new(5)
      assert {:ok, 3} == Pipe.write(pipe, "abc")

      # Refused whole, not truncated to the two bytes that would fit: a
      # partial write would have the caller retry the remainder forever.
      assert :error == Pipe.write(pipe, "defg")
      assert Pipe.size(pipe) == 3
      assert Pipe.seek(pipe, 0) == :ok
      assert Pipe.read(pipe) == "abc"
    end

    test "a write larger than the capacity is refused outright" do
      {:ok, pipe} = Pipe.new(2)
      assert :error == Pipe.write(pipe, "hello")
      assert Pipe.size(pipe) == 0
    end

    test "capacity bounds bytes held, so overwriting in place stays free" do
      {:ok, pipe} = Pipe.new(5)
      assert {:ok, 5} == Pipe.write(pipe, "hello")

      # The pipe is full, but rewriting the same bytes grows nothing.
      assert Pipe.seek(pipe, 0) == :ok
      assert {:ok, 5} == Pipe.write(pipe, "world")
      assert Pipe.size(pipe) == 5

      assert Pipe.seek(pipe, 0) == :ok
      assert Pipe.read(pipe) == "world"
    end

    test "a zero-capacity pipe holds nothing" do
      {:ok, pipe} = Pipe.new(0)
      assert :error == Pipe.write(pipe, "a")
      assert Pipe.size(pipe) == 0
    end
  end
end
