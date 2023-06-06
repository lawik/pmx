defmodule PmxTest do
  use ExUnit.Case
  doctest Pmx

  test "greets the world" do
    System.get_env("REDACTED_PATH")
    |> Path.expand()
    |> Pmx.load_package!("/tmp/nerd-modules")
  end
end
