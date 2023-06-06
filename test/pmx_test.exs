defmodule PmxTest do
  use ExUnit.Case
  doctest Pmx

  test "greets the world" do
    "redacted"
    |> Path.expand()
    |> Pmx.load_package!("/tmp/nerd-modules")
  end
end
