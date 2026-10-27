defmodule Wasmex.Wat do
  @moduledoc """
  Utilities to work with Web Assembly Text (.wat) files.
  """

  @doc """
  Converts a Wasm text file to a Wasm binary.

  Component text uses the current wast syntax. Since the move to wasmtime
  48 (wat 1.262), an export reference inside a canonical option must be
  written as a nested reference: `(memory (core memory $i "name"))`, not
  the legacy `(memory $i "name")`, which now returns an error.
  """
  def to_wasm(wat) do
    case Wasmex.Native.wat_to_wasm(wat) do
      {:error, error} -> {:error, error}
      wasm -> {:ok, wasm}
    end
  end
end
