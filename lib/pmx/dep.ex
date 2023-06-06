defmodule Pmx.Dep do
  defstruct filename: nil,
            package: nil,
            resolved: nil,
            version: nil,
            integrity: nil,
            dev: nil,
            local_file: nil,
            installed_path: nil,
            valid?: false

  alias __MODULE__

  def new({path, detail}) do
    %Dep{
      filename: to_filename(path, detail),
      package: path,
      resolved: detail["resolved"],
      version: detail["version"],
      integrity: detail["integrity"],
      dev: detail["dev"]
    }
  end

  defp to_filename(path, detail) do
    "#{path}-#{detail["version"]}.tgz" |> String.replace("/", "--")
  end
end
